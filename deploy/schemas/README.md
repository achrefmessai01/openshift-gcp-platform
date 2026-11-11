# deploy/schemas — CRD JSON schemas for offline validation

kubeconform validates core Kubernetes kinds from its default schema catalogue, but OpenShift
and Prometheus Operator kinds are custom resources. Their schemas are vendored here so the
validation is reproducible and does not depend on a third-party catalogue being complete.

| File                                           | Source CRD                                                        |
|------------------------------------------------|-------------------------------------------------------------------|
| `route.openshift.io/route_v1.json`             | openshift/api `route/v1/zz_generated.crd-manifests/routes.crd.yaml` |
| `monitoring.coreos.com/servicemonitor_v1.json` | prometheus-operator `monitoring.coreos.com_servicemonitors.yaml`   |
| `monitoring.coreos.com/prometheusrule_v1.json` | prometheus-operator `monitoring.coreos.com_prometheusrules.yaml`   |

Regenerate (for example after an OpenShift upgrade):

```bash
python tools/crd2schema.py \
  https://raw.githubusercontent.com/openshift/api/master/route/v1/zz_generated.crd-manifests/routes.crd.yaml \
  https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml \
  https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_prometheusrules.yaml \
  --out deploy/schemas
```

Use with kubeconform:

```bash
oc kustomize deploy/overlays/prod | kubeconform -strict -summary \
  -schema-location default \
  -schema-location 'deploy/schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```
