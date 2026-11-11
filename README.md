# openshift-gcp-platform

[![ci](https://github.com/achrefmessai01/openshift-gcp-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/achrefmessai01/openshift-gcp-platform/actions/workflows/ci.yml)

End-to-end deployment chain for an **OpenShift 4 cluster on Google Cloud** and a reference
workload on top of it, built the way an integration team delivers a solution to an operator:
the network is declared before it is opened, every environment comes from Git, every delivery
ends with an acceptance record, and operations get a runbook.

```
Terraform (GCP landing zone) ─► openshift-install (IPI, existing VPC) ─► Ansible (day-2)
        │                                                                     │
        └──► GitLab CI / GitHub Actions ─► image (UBI 9, kaniko, Trivy, SBOM) ─► Kustomize deploy
                                            ─► Robot Framework / Bruno / JMeter acceptance ─► records
```

## What is in the repository

| Directory          | Content                                                                                   |
|--------------------|-------------------------------------------------------------------------------------------|
| `terraform/`       | GCP landing zone: VPC, two subnets, Cloud NAT, firewall rules **generated from the flow matrix**, installer/CI service accounts and roles, required APIs, Cloud DNS zone, GCS registry bucket, optional IAP-only bastion |
| `docs/flow-matrix.yaml` | The reviewed flow matrix (matrice de flux): single source for firewall rules and for `docs/flow-matrix.md` |
| `install/`         | OpenShift IPI `install-config.yaml` template rendered from Terraform outputs, create/destroy wrapper |
| `ansible/`         | Day-2 roles: htpasswd identity + admin group, default project template (deny-by-default NetworkPolicies, quota, limits), persistent monitoring + user-workload monitoring + Alertmanager receiver, GCS-backed image registry, ELK through the certified ECK operator (Elasticsearch, Kibana, Filebeat) |
| `app/subscriber-api/` | Reference workload: FastAPI subscriber provisioning API with liveness/readiness, Prometheus metrics, API-key protected writes; UBI 9 image that runs as an arbitrary UID with a read-only root filesystem |
| `deploy/`          | Kustomize base (Deployment, Service, Route, HPA, PDB, NetworkPolicies, ServiceMonitor, PrometheusRule) and dev/staging/prod overlays |
| `tests/robot/`     | Robot Framework acceptance suites: functional/security/observability (`RT-xxx`) and platform (`RP-xxx`) |
| `tests/bruno/`     | Bruno collection (Git-friendly API client) for integration and support                    |
| `tests/jmeter/`    | JMeter load plan with per-endpoint assertions                                            |
| `tools/`           | `flowmatrix.py` (validate/render), `acceptance.py` (runs Robot, writes the acceptance record), `jmeter_gate.py` (thresholds), `netcheck.sh` (L3 diagnostics) |
| `scripts/`         | `deploy.sh`, `rollback.sh` (verified by smoke tests), `bootstrap-state.sh`                |
| `docs/`            | [Engineering document](docs/engineering.md), [flow matrix](docs/flow-matrix.md), [operations runbook](docs/operations.md), [technical acceptance book](docs/acceptance.md), [monthly incident report template](docs/incident-report-template.md) |
| `.gitlab-ci.yml`   | Full chain: lint → test → build → plan → apply → install → day-2 → deploy → acceptance → performance → report, with manual gates and resource groups |
| `.github/workflows/ci.yml` | The validations that run on every push here (see below)                          |

## Quick start (local, no cloud account)

```bash
# sample application
pip install -e "app/subscriber-api[dev]" && pytest app/subscriber-api
docker build -t subscriber-api:dev -f app/subscriber-api/Containerfile app/subscriber-api
docker run -d --name api -p 8080:8080 --user 1000810000:0 --read-only --tmpfs /tmp -e API_KEY=dev subscriber-api:dev

# acceptance record (Robot Framework) and API checks (Bruno)
pip install -r tests/robot/requirements.txt
python tools/acceptance.py --base-url http://localhost:8080 --env local --api-key dev
(cd tests/bruno && npx --yes @usebruno/cli run --env local --env-var apiKey=dev)

# platform code
python tools/flowmatrix.py check
terraform -chdir=terraform init -backend=false && terraform -chdir=terraform validate
kubectl kustomize deploy/overlays/prod
```

`make help` lists every target (`lint`, `test`, `build`, `acceptance`, `perf`, `plan`, `apply`,
`install`, `day2`, `deploy`, `rollback`, `netcheck`).

## Deploying for real

1. `scripts/bootstrap-state.sh <project>` then `terraform -chdir=terraform init -backend-config=...`
2. `cp terraform/terraform.tfvars.example terraform/terraform.tfvars`, set `project_id`,
   `base_domain`, `admin_cidrs`; `terraform plan` / `apply` (review the generated firewall rules).
3. Delegate the base domain to the Cloud DNS name servers (`terraform output dns_name_servers`).
4. `PULL_SECRET_FILE=... install/render-install-config.sh --create` (about 40 minutes).
5. `cd ansible && ansible-playbook site.yml` (identity, projects, monitoring, registry, logging).
6. `API_KEY=... scripts/deploy.sh dev --acceptance`, then promote through staging and prod with
   the pipeline.

Cost: the default sizing (3 + 3 × n2-standard-4, load balancers, NAT) is roughly USD 1 per
hour; destroy with `install/render-install-config.sh --destroy` and `terraform destroy`.

## Validation status

Being explicit about what has actually been executed matters more than a long feature list.

| Check                                                                 | Where it ran                        |
|-----------------------------------------------------------------------|-------------------------------------|
| Unit tests (pytest), ruff, yamllint, flow-matrix consistency           | locally and in GitHub Actions       |
| `terraform fmt` / `validate`                                           | locally and in GitHub Actions       |
| `terraform plan` against a real GCP project (45 resources, read-only)  | locally                             |
| `kustomize build` of the three overlays                                | locally and in GitHub Actions       |
| `kubeconform` with Kubernetes + OpenShift/Prometheus CRD schemas       | GitHub Actions                      |
| Ansible syntax check and ansible-lint                                  | GitHub Actions (and locally in a container) |
| Image build (UBI 9) and run as UID 1000810000 / GID 0, read-only root FS | locally and in GitHub Actions     |
| Robot Framework suites RT-xxx against the running container (13/13)    | locally and in GitHub Actions       |
| Bruno collection (10 requests, 13 assertions)                          | locally and in GitHub Actions       |
| JMeter 20-user smoke load with error-rate and p95 gates                | GitHub Actions                      |
| Image push to GHCR + Trivy critical-CVE gate                           | GitHub Actions (on push to `main`)  |

Not yet executed, because they need a paid OpenShift cluster: `terraform apply`,
`openshift-install`, the Ansible playbook against a live cluster (including the ELK stack),
the platform suite `RP-xxx` and the production JMeter run. The code for these stages is
written to the OpenShift and ECK documentation and is wired into the pipeline so that the
first real run produces the same records as the local ones.

## Design choices worth knowing

- **Flow matrix as code**: `docs/flow-matrix.yaml` is validated, rendered to Markdown and
  turned into one VPC firewall rule per flow; egress is allow-listed with a logged default deny.
- **OpenShift-native workload**: no fixed UID, group-0 ownership, dropped capabilities,
  read-only root filesystem, deny-by-default NetworkPolicies, edge-TLS Route with HSTS,
  ServiceMonitor and PrometheusRule for user-workload monitoring.
- **Acceptance as a record, not a log**: `tools/acceptance.py` turns Robot results into a
  dated acceptance record (Markdown + JSON) whose test ids match the acceptance book.
- **Verified rollback**: `scripts/rollback.sh` reverts the Deployment and re-runs the smoke suite.
- **Two pipelines, one chain**: GitLab CI carries the full chain with manual gates; GitHub
  Actions runs everything that can run without a cluster so this repository stays green.

## License

MIT, see [LICENSE](LICENSE).
