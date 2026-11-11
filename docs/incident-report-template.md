# Monthly incident report (rapport mensuel d'incidents) — template

| Item        | Value                           |
|-------------|---------------------------------|
| Service     | subscriber-api on OpenShift / GCP |
| Period      | YYYY-MM                         |
| Author      |                                 |
| Distribution| Customer, operations, L3 team   |

## 1. Summary

Two or three sentences: overall service health, notable incidents, main actions.

## 2. Key figures

| Indicator                         | This month | Previous month | Target  |
|-----------------------------------|------------|----------------|---------|
| Tickets opened / closed           |            |                |         |
| P1 / P2 / P3 / P4                 |            |                |         |
| Mean time to acknowledge (MTTA)   |            |                | 15 min (P1) |
| Mean time to restore (MTTR)       |            |                | 4 h (P2) |
| Availability of the Route (%)     |            |                | 99.9 %  |
| Alerts fired / acknowledged       |            |                |         |
| Deployments / rollbacks           |            |                |         |

Availability source: `avg_over_time(up{job="subscriber-api"}[30d])` and synthetic checks.

## 3. Incidents

| ID       | Date       | Priority | Component        | Duration | Impact                     | Root cause                     | Status  |
|----------|------------|----------|------------------|----------|----------------------------|--------------------------------|---------|
| INC-0001 |            |          |                  |          |                            |                                |         |

## 4. Post-incident reviews (P1/P2)

### INC-xxxx — title

- **Timeline**: detection (alert / user), acknowledgement, mitigation, resolution.
- **Root cause**:
- **What worked**:
- **What did not**:
- **Actions** (owner, due date):

## 5. Problems and recurring issues

| Problem | Related incidents | Workaround | Permanent fix (owner, date) |
|---------|-------------------|------------|-----------------------------|

## 6. Changes of the month

| Date | Change (MR / ticket) | Environment | Result (acceptance record) |
|------|----------------------|-------------|----------------------------|

## 7. Capacity and security

- Cluster CPU/memory usage (max, average), HPA activity, NAT port usage.
- Image scan results (critical/high CVEs), certificate expiries within 90 days, OpenShift
  version and next upgrade window.

## 8. Next month

- Planned maintenance, upgrades, pending actions from sections 4 and 5.
