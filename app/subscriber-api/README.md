# subscriber-api

A small subscriber provisioning API (telecom flavoured: MSISDN, plan, status) used as the
reference workload for the OpenShift-on-GCP delivery chain. It is deliberately simple so the
platform work around it (image, manifests, tests, pipeline, documentation) stays the focus.

## Endpoints

| Method | Path                                   | Auth      | Description                                  |
|--------|----------------------------------------|-----------|----------------------------------------------|
| GET    | `/healthz`                             | none      | Liveness: process is alive                    |
| GET    | `/readyz`                              | none      | Readiness: 200 while serving, 503 on shutdown |
| GET    | `/metrics`                             | none      | Prometheus metrics                            |
| GET    | `/api/v1/info`                         | none      | Service name, version, environment, hostname  |
| GET    | `/api/v1/subscribers`                  | none      | List subscribers (optional `?status=`)        |
| POST   | `/api/v1/subscribers`                  | API key   | Create a subscriber (201, 409 on duplicate)   |
| GET    | `/api/v1/subscribers/{msisdn}`         | none      | Get one subscriber (404 if unknown)           |
| POST   | `/api/v1/subscribers/{msisdn}/suspend` | API key   | Suspend                                       |
| POST   | `/api/v1/subscribers/{msisdn}/activate`| API key   | Re-activate                                   |
| DELETE | `/api/v1/subscribers/{msisdn}`         | API key   | Delete (204)                                  |

Write operations require the `X-API-Key` header when the `API_KEY` environment variable is
set (it is injected from a Secret on OpenShift). Without `API_KEY` the API is open, which is
only acceptable for local development.

## Configuration (environment variables)

| Variable      | Default        | Purpose                                      |
|---------------|----------------|----------------------------------------------|
| `APP_ENV`     | `local`        | Reported by `/api/v1/info`, used in metrics   |
| `APP_VERSION` | package version| Reported by `/api/v1/info`                    |
| `API_KEY`     | unset          | Enables API-key protection of write endpoints |
| `LOG_LEVEL`   | `INFO`         | Python logging level                          |
| `PORT`        | `8080`         | Listening port (uvicorn)                      |

## Run locally

```bash
pip install -e ".[dev]"
uvicorn subscriber_api.main:app --host 0.0.0.0 --port 8080
pytest
```

## Container image

The `Containerfile` builds on the Red Hat UBI 9 Python image, runs as a non-root user and is
compatible with OpenShift's `restricted-v2` SCC (arbitrary UID, group 0, no privilege
escalation). Build and run:

```bash
podman build -t subscriber-api:dev -f Containerfile .
podman run --rm -p 8080:8080 --user 1000810000:0 subscriber-api:dev
```
