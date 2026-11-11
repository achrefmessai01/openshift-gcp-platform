# Flow matrix (matrice de flux)

> Generated from `docs/flow-matrix.yaml` by `python tools/flowmatrix.py render`. Do not edit by hand.

- Platform: **openshift-gcp-platform**
- Owner: platform-team
- Last review: 2026-11-11

## Zones

| Alias | Meaning |
|-------|---------|
| `control_plane` | Control-plane subnet |
| `compute` | Compute (worker) subnet |
| `admin` | Administration and CI networks |
| `internet` | Any public address |
| `gcp_health_checks` | Google Cloud load balancer health checkers |
| `gcp_iap` | Google Identity-Aware Proxy TCP forwarding |

## Flows

Each line is implemented as one VPC firewall rule named `<prefix>-<id>-<name>`.

| ID | Name | Dir | Action | Prio | Source | Destination | Protocol / ports | Log | Description | Justification |
|----|------|-----|--------|------|--------|-------------|------------------|-----|-------------|---------------|
| FW-001 | `api-admin` | INGRESS | allow | 1000 | `admin` | `control_plane` | tcp 6443 | yes | OpenShift API (Kubernetes API server) from administration and CI networks | Cluster administration (oc, Ansible), pipeline deployments |
| FW-002 | `api-internal` | INGRESS | allow | 1000 | `control_plane`, `compute` | `control_plane` | tcp 6443, 22623 |  | API server and machine config server from cluster nodes | kubelets reach the API; nodes fetch their ignition from the MCS on 22623 |
| FW-003 | `lb-health-checks` | INGRESS | allow | 1000 | `gcp_health_checks` | `control_plane`, `compute` | tcp 6080, 6443, 22624, 30000-32767 |  | Google load balancer health checks towards API, MCS and router node ports | Internal/external API load balancers and the ingress load balancer probe the nodes |
| FW-004 | `etcd` | INGRESS | allow | 1000 | `control_plane` | `control_plane` | tcp 2379-2380 |  | etcd client and peer traffic between control-plane nodes | etcd quorum and API server backend |
| FW-005 | `control-plane-services` | INGRESS | allow | 1000 | `control_plane`, `compute` | `control_plane` | tcp 10257, 10259 |  | kube-controller-manager and kube-scheduler endpoints | Health and metrics endpoints of the control-plane components |
| FW-006 | `cluster-internal` | INGRESS | allow | 1000 | `control_plane`, `compute` | `control_plane`, `compute` | tcp 22, 9000-9999, 10250, 10256, 30000-32767<br>udp 4789, 6081, 500, 4500, 9000-9999, 30000-32767<br>esp |  | Node-to-node traffic required by OpenShift (kubelet, host services, overlay, node ports, IPsec) | Kubelet (10250), host-level metrics (9000-9999), VXLAN/Geneve overlay, IPsec, NodePort services |
| FW-007 | `ingress-public` | INGRESS | allow | 1000 | `internet` | `compute` | tcp 80, 443 | yes | Application traffic to the OpenShift router (HTTP redirected to HTTPS) | Public exposure of Routes (*.apps) through the ingress load balancer |
| FW-008 | `ssh-iap` | INGRESS | allow | 1000 | `gcp_iap` | `control_plane`, `compute` | tcp 22 | yes | SSH to nodes and bastion through Identity-Aware Proxy TCP forwarding | Level-3 troubleshooting without public IPs (gcloud compute ssh --tunnel-through-iap) |
| FW-009 | `egress-web` | EGRESS | allow | 1000 | `control_plane`, `compute` | `internet` | tcp 80, 443 |  | Outbound HTTP/HTTPS from nodes through Cloud NAT | Image pulls (quay.io, registry.redhat.io), Red Hat telemetry/OCM, Google APIs, OperatorHub catalogs |
| FW-010 | `egress-time-dns` | EGRESS | allow | 1000 | `control_plane`, `compute` | `internet` | udp 123, 53<br>tcp 53 |  | Outbound NTP and DNS | Chrony time sync and upstream DNS forwarding (metadata server resolver is implicitly allowed) |
| FW-011 | `egress-cluster` | EGRESS | allow | 1000 | `control_plane`, `compute` | `control_plane`, `compute` | all |  | All outbound traffic between cluster subnets | Mirror of FW-002/004/005/006 on the egress side once default egress is denied |
| FW-099 | `egress-default-deny` | EGRESS | deny | 65000 | `control_plane`, `compute` | `internet` | all | yes | Deny every other outbound flow (explicit allow-list policy) | Enforces the matrix; new outbound needs are added above as reviewed flows |

## Change procedure

1. Open a merge request editing `docs/flow-matrix.yaml` (new flow id, justification, owner).
2. CI validates the matrix and regenerates this document; `terraform plan` shows the resulting rule.
3. Network/security review on the merge request, then `terraform apply` from the pipeline.
