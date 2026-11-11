# ansible/ — day-2 configuration of the cluster

Idempotent playbook run from a workstation, the bastion or a CI runner against the
OpenShift API (no SSH to the nodes).

| Role                   | What it configures                                                                 |
|------------------------|------------------------------------------------------------------------------------|
| `ocp_identity`         | htpasswd identity provider, `platform-admins` group bound to `cluster-admin`, token lifetime, removal of `kubeadmin` |
| `ocp_project_template` | Default project template: admin RoleBinding, default-deny NetworkPolicies, ResourceQuota, LimitRange |
| `ocp_monitoring`       | Persistent platform Prometheus/Alertmanager, user-workload monitoring, Alertmanager webhook receiver |
| `ocp_registry`         | Internal image registry on the Terraform-created GCS bucket, 2 replicas, rolling updates |
| `ocp_logging`          | ELK through the certified ECK operator: Elasticsearch, Kibana (Route), Filebeat DaemonSet with the privileged SCC |

## Run

```bash
cd ansible
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml
cp group_vars/all/vault.yml.example group_vars/all/vault.yml   # fill in, then:
ansible-vault encrypt group_vars/all/vault.yml

export KUBECONFIG=../install/ocp/auth/kubeconfig
export REGISTRY_BUCKET=$(terraform -chdir=../terraform output -raw registry_bucket)
ansible-playbook site.yml --ask-vault-pass            # or --vault-password-file
ansible-playbook site.yml --tags monitoring --check --diff
```

## Checks run in CI

```bash
ansible-playbook --syntax-check site.yml
ansible-lint
```
