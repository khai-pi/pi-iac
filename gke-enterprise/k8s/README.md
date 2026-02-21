# k8s-config — GitOps Repository

This repository is the single source of truth for all Kubernetes cluster state.
**No manual `kubectl apply` in production. All changes go through Git → ArgoCD → cluster.**

## Repository Structure

```
k8s-config/
│
├── cluster/                    # Cluster-scoped resources (applied by platform team only)
│   ├── crds/                   # Custom Resource Definitions
│   ├── rbac/                   # ClusterRoles, ClusterRoleBindings
│   ├── namespaces/             # Namespace definitions
│   └── policies/               # Gatekeeper ConstraintTemplates + Constraints
│
├── platform/                   # Platform component configurations
│   ├── argocd/                 # ArgoCD ApplicationSets, Projects, root app
│   ├── cert-manager/           # ClusterIssuers, certificates
│   ├── external-secrets/       # ClusterSecretStore
│   ├── monitoring/             # Prometheus rules, Grafana dashboards, alerting
│   ├── ingress/                # Gateway, HTTPRoutes for platform services
│   ├── service-mesh/           # ASM PeerAuthentication, AuthorizationPolicies
│   ├── vpa/                    # VerticalPodAutoscaler objects
│   └── gatekeeper/             # OPA constraint templates and constraints
│
├── namespaces/                 # Per-team namespace resources (quotas, RBAC, netpol)
│   ├── team-payments/
│   ├── team-identity/
│   └── team-data/
│
└── apps/                       # ArgoCD Application manifests per team
    ├── team-payments/
    ├── team-identity/
    └── team-data/
```

## Sync Strategy

- **Cluster resources** — synced by ArgoCD `platform-cluster` app, auto-sync with pruning
- **Platform components** — synced by ArgoCD `platform-components` app, auto-sync
- **Namespace resources** — synced by ArgoCD per-team apps, auto-sync with self-heal
- **Application workloads** — synced by ArgoCD per-app Applications, canary via Argo Rollouts

## Making Changes

```bash
# 1. Create a branch
git checkout -b feat/your-change

# 2. Make changes and validate
kubectl apply --dry-run=client -f path/to/manifest.yaml
kubectl diff -f path/to/manifest.yaml   # against live cluster (if you have access)

# 3. Push and open PR
# CI runs: kubeval, conftest (OPA), kube-score

# 4. After merge, ArgoCD syncs within 30 seconds
argocd app sync <app-name>   # or wait for auto-sync
```

## CI Checks

Every PR runs:
- `kubeval` — schema validation against Kubernetes API
- `conftest` — OPA policy checks (resource limits required, no latest tag, etc.)
- `kube-score` — best practices scoring
- `helm lint` — for any Helm chart values files
