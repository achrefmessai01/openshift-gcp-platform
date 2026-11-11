# install/ — OpenShift cluster installation (IPI on GCP, existing VPC)

The installer-provisioned infrastructure (IPI) workflow creates the control plane, the
worker MachineSets, the API and ingress load balancers and the DNS records, inside the VPC
and subnets created by `terraform/` (`platform.gcp.network`, `controlPlaneSubnet`,
`computeSubnet`).

## Prerequisites

1. `terraform apply` done; `terraform output install_config` returns the network names.
2. Base domain delegated to the Cloud DNS name servers (`terraform output dns_name_servers`).
3. A Red Hat pull secret (console.redhat.com → OpenShift → Downloads) in `PULL_SECRET_FILE`.
4. Credentials for the installer service account (`terraform output installer_service_account`):

   ```bash
   gcloud iam service-accounts keys create ~/.gcp/osServiceAccount.json \
     --iam-account "$(terraform -chdir=terraform output -raw installer_service_account)"
   export GOOGLE_CREDENTIALS=~/.gcp/osServiceAccount.json
   ```

   Keys are a liability: rotate after the installation or prefer `credentialsMode: Manual`
   with short-lived credentials for production clusters.
5. `openshift-install` and `oc` matching the target OpenShift version (mirror.openshift.com).

## Create

```bash
PULL_SECRET_FILE=~/pull-secret.json install/render-install-config.sh --create
export KUBECONFIG=install/ocp/auth/kubeconfig
oc get clusterversion && oc get nodes
```

Sizing defaults (overridable through environment variables): 3 × n2-standard-4 control
plane, 3 × n2-standard-4 workers, pd-ssd 128 GB, OVN-Kubernetes, `publish: External`.
For a private cluster set `PUBLISH=Internal` (API and `*.apps` only reachable from the VPC
or through the bastion).

## Destroy

```bash
install/render-install-config.sh --destroy
```

## Day-2 configuration

Once the cluster is up, run the Ansible playbook (`ansible/`) to configure identity, the
default project template, monitoring, the image registry and logging.
