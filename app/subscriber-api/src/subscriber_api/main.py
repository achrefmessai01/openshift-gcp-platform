"""FastAPI application: subscriber provisioning API.

Operational contract expected by the platform (probes, metrics, graceful shutdown):

* ``GET /healthz``  liveness, always 200 while the process runs
* ``GET /readyz``   readiness, 200 while serving, 503 once shutdown has started so the
                    router/Service stops sending new traffic before the process exits
* ``GET /metrics``  Prometheus exposition, scraped by a ServiceMonitor
"""

from __future__ import annotations

import logging
import os
import socket
import time
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager
from datetime import UTC, datetime

from fastapi import Depends, FastAPI, HTTPException, Query, Request, Response, status
from fastapi.responses import JSONResponse
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest

from . import __version__
from .models import (
    Info,
    Problem,
    Subscriber,
    SubscriberCreate,
    SubscriberList,
    SubscriberStatus,
)
from .store import DuplicateSubscriber, SubscriberStore, UnknownSubscriber

SERVICE_NAME = "subscriber-api"
APP_ENV = os.getenv("APP_ENV", "local")
APP_VERSION = os.getenv("APP_VERSION", __version__)
API_KEY = os.getenv("API_KEY") or None
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()

logging.basicConfig(
    level=LOG_LEVEL,
    format='{"ts":"%(asctime)s","level":"%(levelname)s","logger":"%(name)s","msg":"%(message)s"}',
)
log = logging.getLogger(SERVICE_NAME)

# --- Metrics ---------------------------------------------------------------------------------
HTTP_REQUESTS = Counter(
    "http_requests_total",
    "HTTP requests by method, route template and status code",
    ["method", "route", "status"],
)
HTTP_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds by route template",
    ["method", "route"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5),
)
SUBSCRIBERS = Gauge("subscribers_total", "Subscribers currently stored")
BUILD_INFO = Gauge("subscriber_api_build_info", "Build information", ["version", "environment"])
BUILD_INFO.labels(version=APP_VERSION, environment=APP_ENV).set(1)


class State:
    ready: bool = False
    started_at: datetime = datetime.now(tz=UTC)


state = State()
store = SubscriberStore()


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    state.started_at = datetime.now(tz=UTC)
    state.ready = True
    log.info("startup complete env=%s version=%s", APP_ENV, APP_VERSION)
    yield
    # Flip readiness first; the platform's readiness probe will drain traffic during the
    # termination grace period while in-flight requests complete.
    state.ready = False
    log.info("shutdown: readiness set to false")


app = FastAPI(
    title="Subscriber API",
    version=APP_VERSION,
    lifespan=lifespan,
    responses={status.HTTP_401_UNAUTHORIZED: {"model": Problem}},
)


# --- Middleware ------------------------------------------------------------------------------
@app.middleware("http")
async def metrics_middleware(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    start = time.perf_counter()
    response = await call_next(request)
    route = request.scope.get("route")
    template = getattr(route, "path", request.url.path)
    HTTP_REQUESTS.labels(request.method, template, str(response.status_code)).inc()
    HTTP_LATENCY.labels(request.method, template).observe(time.perf_counter() - start)
    return response


# --- Error handling --------------------------------------------------------------------------
@app.exception_handler(HTTPException)
async def problem_handler(_: Request, exc: HTTPException) -> JSONResponse:
    body = Problem(title=exc.detail if isinstance(exc.detail, str) else "error", status=exc.status_code)
    return JSONResponse(status_code=exc.status_code, content=body.model_dump(), headers=exc.headers)


# --- Auth ------------------------------------------------------------------------------------
async def require_api_key(request: Request) -> None:
    """Protect write endpoints with a static API key when one is configured."""
    if API_KEY is None:
        return
    if request.headers.get("x-api-key") != API_KEY:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="invalid or missing API key",
            headers={"WWW-Authenticate": "ApiKey"},
        )


# --- Platform endpoints ----------------------------------------------------------------------
@app.get("/healthz", tags=["platform"], include_in_schema=False)
async def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/readyz", tags=["platform"], include_in_schema=False)
async def readyz() -> JSONResponse:
    if not state.ready:
        return JSONResponse(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, content={"status": "draining"})
    return JSONResponse(content={"status": "ready"})


@app.get("/metrics", tags=["platform"], include_in_schema=False)
async def metrics() -> Response:
    SUBSCRIBERS.set(store.count())
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/api/v1/info", response_model=Info, tags=["platform"])
async def info() -> Info:
    return Info(
        service=SERVICE_NAME,
        version=APP_VERSION,
        environment=APP_ENV,
        hostname=socket.gethostname(),
        started_at=state.started_at,
    )


# --- Business endpoints ----------------------------------------------------------------------
@app.get("/api/v1/subscribers", response_model=SubscriberList, tags=["subscribers"])
async def list_subscribers(
    status_filter: SubscriberStatus | None = Query(default=None, alias="status"),
) -> SubscriberList:
    items = store.list(status_filter)
    return SubscriberList(items=items, total=len(items))


@app.post(
    "/api/v1/subscribers",
    response_model=Subscriber,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(require_api_key)],
    tags=["subscribers"],
)
async def create_subscriber(payload: SubscriberCreate) -> Subscriber:
    try:
        sub = store.create(payload)
    except DuplicateSubscriber as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="subscriber already exists") from exc
    log.info("subscriber created msisdn=%s plan=%s", sub.msisdn, sub.plan)
    return sub


@app.get("/api/v1/subscribers/{msisdn}", response_model=Subscriber, tags=["subscribers"])
async def get_subscriber(msisdn: str) -> Subscriber:
    try:
        return store.get(msisdn)
    except UnknownSubscriber as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="subscriber not found") from exc


def _set_status(msisdn: str, new_status: SubscriberStatus) -> Subscriber:
    try:
        sub = store.set_status(msisdn, new_status)
    except UnknownSubscriber as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="subscriber not found") from exc
    log.info("subscriber status changed msisdn=%s status=%s", msisdn, new_status.value)
    return sub


@app.post(
    "/api/v1/subscribers/{msisdn}/suspend",
    response_model=Subscriber,
    dependencies=[Depends(require_api_key)],
    tags=["subscribers"],
)
async def suspend_subscriber(msisdn: str) -> Subscriber:
    return _set_status(msisdn, SubscriberStatus.SUSPENDED)


@app.post(
    "/api/v1/subscribers/{msisdn}/activate",
    response_model=Subscriber,
    dependencies=[Depends(require_api_key)],
    tags=["subscribers"],
)
async def activate_subscriber(msisdn: str) -> Subscriber:
    return _set_status(msisdn, SubscriberStatus.ACTIVE)


@app.delete(
    "/api/v1/subscribers/{msisdn}",
    status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(require_api_key)],
    tags=["subscribers"],
)
async def delete_subscriber(msisdn: str) -> Response:
    try:
        store.delete(msisdn)
    except UnknownSubscriber as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="subscriber not found") from exc
    log.info("subscriber deleted msisdn=%s", msisdn)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
