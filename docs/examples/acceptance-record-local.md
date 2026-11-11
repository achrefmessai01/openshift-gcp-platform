# Acceptance record — local

- Target: `http://127.0.0.1:8089`
- Executed: 2026-11-11T17:11:13+00:00
- Generator: Robot 7.5.1 (Python 3.13.5 on win32)
- Result: **ACCEPTED** (13 passed, 0 failed, 6 skipped, 19 total)

| ID | Test | Tags | Status | Time (s) | Message |
|----|------|------|--------|----------|---------|
| RP-001 | RP-001 Plain HTTP on the Route is redirected to HTTPS | platform | SKIP | 0.0 | ROUTE_HOST not set |
| RP-002 | RP-002 HTTPS responses carry an HSTS header | platform | SKIP | 0.0 | ROUTE_HOST not set |
| RP-003 | RP-003 Route certificate is valid for more than 14 days | platform | SKIP | 0.0 | ROUTE_HOST not set |
| RP-004 | RP-004 Route serves the application over HTTPS | platform | SKIP | 0.0 | ROUTE_HOST not set |
| RP-010 | RP-010 OpenShift API server is reachable and healthy | platform | SKIP | 0.0 | API_URL not set |
| RP-011 | RP-011 OpenShift API server rejects anonymous access to cluster resources | platform | SKIP | 0.0 | API_URL not set |
| RT-001 | RT-001 Liveness endpoint answers 200 | smoke, subscriber-api | PASS | 0.01 |  |
| RT-002 | RT-002 Readiness endpoint answers 200 | smoke, subscriber-api | PASS | 0.0 |  |
| RT-003 | RT-003 Info endpoint identifies the service and its environment | smoke, subscriber-api | PASS | 0.01 |  |
| RT-010 | RT-010 Creating a subscriber returns 201 and an ACTIVE record | functional, subscriber-api | PASS | 0.01 |  |
| RT-011 | RT-011 Creating the same subscriber twice is rejected with 409 | functional, subscriber-api | PASS | 0.01 |  |
| RT-012 | RT-012 A created subscriber can be read back | functional, subscriber-api | PASS | 0.0 |  |
| RT-013 | RT-013 Listing supports filtering by status | functional, subscriber-api | PASS | 0.03 |  |
| RT-014 | RT-014 Suspending then re-activating updates the status and timestamp | functional, subscriber-api | PASS | 0.01 |  |
| RT-015 | RT-015 Deleting a subscriber returns 204 and the record disappears | functional, subscriber-api | PASS | 0.01 |  |
| RT-020 | RT-020 Invalid MSISDN or plan is rejected with 422 | functional, security, subscriber-api | PASS | 0.01 |  |
| RT-021 | RT-021 Write operations without a valid API key are rejected with 401 | security, subscriber-api | PASS | 0.01 |  |
| RT-030 | RT-030 Metrics endpoint exposes Prometheus counters for the API | observability, subscriber-api | PASS | 0.01 |  |
| RT-031 | RT-031 Error responses use the problem format | functional, subscriber-api | PASS | 0.0 |  |

Sign-off (name / date / decision): ________________________________
