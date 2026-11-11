# deploy/ — OpenShift manifests (Kustomize)

```
deploy/
├── base/                 # environment-agnostic manifests
│   ├── deployment.yaml   # restricted-v2 compatible, probes, spread constraints, read-only FS
│   ├── service.yaml
│   ├── route.yaml        # edge TLS, HTTP→HTTPS redirect, HSTS
│   ├── hpa.yaml          # CPU based autoscaling
│   ├── pdb.yaml
│   ├── networkpolicy.yaml# default deny + router + monitoring + same namespace
│   ├── servicemonitor.yaml
│   ├── prometheusrule.yaml
│   ├── configmap.yaml
│   └── serviceaccount.yaml
└── overlays/
    ├── dev/              # 1 replica, latest image, debug logs
    ├── staging/          # release candidate tag, prod-like sizing
    └── prod/             # 3 replicas, zone-hard spread, pinned host, rate limiting
```

Render and inspect an environment:

```bash
oc kustomize deploy/overlays/dev
```

Deploy (the pipeline does exactly this through `scripts/deploy.sh`):

```bash
oc new-project subscriber-api-dev            # first time only
oc -n subscriber-api-dev create secret generic subscriber-api-secrets --from-literal=API_KEY=...
oc apply -k deploy/overlays/dev
oc -n subscriber-api-dev rollout status deployment/subscriber-api
```

Offline validation (what CI runs):

```bash
oc kustomize deploy/overlays/prod | kubeconform -strict -summary \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```

The second schema location provides the OpenShift `Route` and the Prometheus Operator
`ServiceMonitor` / `PrometheusRule` CRD schemas.
