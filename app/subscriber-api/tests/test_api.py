"""Unit tests for the subscriber API (run with pytest)."""

from __future__ import annotations

from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient
from subscriber_api import main

MSISDN = "+21650123456"
HEADERS = {"X-API-Key": "test-key"}


@pytest.fixture()
def client() -> Iterator[TestClient]:
    main.store = main.SubscriberStore()  # isolate every test
    with TestClient(main.app) as c:
        yield c


def test_liveness_and_readiness(client: TestClient) -> None:
    assert client.get("/healthz").json() == {"status": "ok"}
    assert client.get("/readyz").status_code == 200


def test_info_reports_environment(client: TestClient) -> None:
    body = client.get("/api/v1/info").json()
    assert body["service"] == "subscriber-api"
    assert body["environment"] == "test"
    assert body["version"]


def test_create_get_delete_lifecycle(client: TestClient) -> None:
    created = client.post("/api/v1/subscribers", json={"msisdn": MSISDN, "plan": "PREPAID_5GB"}, headers=HEADERS)
    assert created.status_code == 201
    assert created.json()["status"] == "ACTIVE"

    assert client.get(f"/api/v1/subscribers/{MSISDN}").json()["plan"] == "PREPAID_5GB"

    listed = client.get("/api/v1/subscribers").json()
    assert listed["total"] == 1

    suspended = client.post(f"/api/v1/subscribers/{MSISDN}/suspend", headers=HEADERS)
    assert suspended.json()["status"] == "SUSPENDED"
    assert client.get("/api/v1/subscribers", params={"status": "ACTIVE"}).json()["total"] == 0
    assert client.get("/api/v1/subscribers", params={"status": "SUSPENDED"}).json()["total"] == 1

    activated = client.post(f"/api/v1/subscribers/{MSISDN}/activate", headers=HEADERS)
    assert activated.json()["status"] == "ACTIVE"

    assert client.delete(f"/api/v1/subscribers/{MSISDN}", headers=HEADERS).status_code == 204
    assert client.get(f"/api/v1/subscribers/{MSISDN}").status_code == 404


def test_duplicate_is_rejected(client: TestClient) -> None:
    payload = {"msisdn": MSISDN, "plan": "PREPAID_5GB"}
    assert client.post("/api/v1/subscribers", json=payload, headers=HEADERS).status_code == 201
    dup = client.post("/api/v1/subscribers", json=payload, headers=HEADERS)
    assert dup.status_code == 409
    assert dup.json()["title"] == "subscriber already exists"


@pytest.mark.parametrize(
    "payload",
    [
        {"msisdn": "0021650123456", "plan": "PREPAID_5GB"},  # not E.164
        {"msisdn": "+216", "plan": "PREPAID_5GB"},  # too short
        {"msisdn": MSISDN, "plan": "prepaid"},  # plan code must be upper-case
        {"msisdn": MSISDN, "plan": "PREPAID_5GB", "extra": 1},  # unknown field
    ],
)
def test_validation_errors(client: TestClient, payload: dict) -> None:
    assert client.post("/api/v1/subscribers", json=payload, headers=HEADERS).status_code == 422


def test_write_requires_api_key(client: TestClient) -> None:
    resp = client.post("/api/v1/subscribers", json={"msisdn": MSISDN, "plan": "PREPAID_5GB"})
    assert resp.status_code == 401
    assert resp.headers["www-authenticate"] == "ApiKey"
    assert client.delete(f"/api/v1/subscribers/{MSISDN}", headers={"X-API-Key": "wrong"}).status_code == 401


def test_metrics_exposed(client: TestClient) -> None:
    client.get("/healthz")
    text = client.get("/metrics").text
    assert 'http_requests_total{method="GET",route="/healthz",status="200"}' in text
    assert "http_request_duration_seconds_bucket" in text
    assert 'subscriber_api_build_info{environment="test"' in text
