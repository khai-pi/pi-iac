# Runbook: Disaster Recovery Failover

**Severity:** P1
**Approval required:** Engineering Director

> ⚠️ **Declare a P1 incident before initiating failover. Get approval from Engineering Director. Document all actions with timestamps.**

---

## Failover Decision Criteria

Initiate full regional failover **only when ALL of the following are true:**

- [ ] Primary region (`europe-west1`) API server unreachable for **> 10 minutes**
- [ ] GCP Status Dashboard shows confirmed regional impairment at [status.cloud.google.com](https://status.cloud.google.com)
- [ ] DR cluster (`us-central1`) is healthy — all nodes Ready, all platform pods Running
- [ ] Engineering Director has given verbal or written approval

---

## Pre-Failover Checks

```bash
# Switch to DR cluster context
gcloud container clusters get-credentials prod-cluster-dr \
  --region=us-central1 \
  --project=myorg-gke-prod

# Verify DR cluster health
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed

# Check platform components are healthy in DR
kubectl get pods -n argocd
kubectl get pods -n cert-manager
kubectl get pods -n monitoring
kubectl get pods -n external-secrets

# Verify Multi-cluster Ingress backend services are ready
kubectl get backendconfig -A
```

---

## Failover Steps

### 1. Scale Up DR Node Pools

```bash
# Increase min nodes to handle full production traffic
gcloud container node-pools update general-pool \
  --cluster=prod-cluster-dr \
  --region=us-central1 \
  --min-nodes=5

gcloud container node-pools update system-pool \
  --cluster=prod-cluster-dr \
  --region=us-central1 \
  --min-nodes=2

# Wait for nodes to be Ready
kubectl get nodes -w
```

### 2. Shift Traffic to DR

Edit the `k8s-config` GitOps repo to route all traffic to the DR cluster:

```yaml
# k8s-config/cluster/multi-cluster-ingress.yaml
# Remove primary cluster backend, keep only DR
apiVersion: networking.gke.io/v1
kind: MultiClusterIngress
metadata:
  name: platform-ingress
  namespace: gateway
spec:
  template:
    spec:
      backend:
        serviceName: platform-backend-dr   # DR only
        servicePort: 80
```

Merge the PR. Config Sync applies within 60 seconds.

```bash
# Verify traffic is routing to DR
kubectl get multiclusteringress -n gateway
kubectl describe multiclusteringress platform-ingress -n gateway
```

### 3. Verify Services

```bash
# Check all critical services are responding
curl -s https://api.payments.example.com/health
curl -s https://api.identity.example.com/health

# Check error rate in Cloud Monitoring (target: < 1%)
# https://console.cloud.google.com/monitoring

# Check ArgoCD is synced in DR
argocd app list
```

### 4. Communicate

```
Post in #incidents-prod:

🔄 FAILOVER COMPLETE
DR cluster (us-central1) is now serving 100% of production traffic.
Primary region (europe-west1) is being investigated.
Impact duration: [HH:MM – HH:MM UTC]
```

Notify all application team leads via `#platform-announcements`.

---

## Failback Steps (once primary region is restored)

> Wait for explicit confirmation from GCP that the primary region is fully stable before starting failback.

### 1. Verify Primary Cluster

```bash
# Switch back to primary cluster
gcloud container clusters get-credentials prod-cluster-primary \
  --region=europe-west1 \
  --project=myorg-gke-prod

# Confirm all nodes are Ready
kubectl get nodes

# Confirm all platform components are healthy
kubectl get pods -A | grep -v Running | grep -v Completed

# Check ArgoCD has fully synced
argocd app list
```

### 2. Gradual Traffic Shift Back

Do **not** switch all traffic back instantly. Shift gradually to detect any latent issues.

```bash
# Step 1: 10% to primary, 90% DR (edit MultiClusterIngress weights)
# Wait 30 minutes, monitor error rate

# Step 2: 50% / 50%
# Wait 30 minutes, monitor error rate

# Step 3: 90% primary, 10% DR
# Wait 60 minutes, monitor

# Step 4: 100% primary (restore original config)
```

### 3. Scale Down DR

```bash
# Return DR node pools to baseline
gcloud container node-pools update general-pool \
  --cluster=prod-cluster-dr \
  --region=us-central1 \
  --min-nodes=1

gcloud container node-pools update system-pool \
  --cluster=prod-cluster-dr \
  --region=us-central1 \
  --min-nodes=1
```

### 4. Post-Failback

```
Post in #incidents-prod:

✅ FAILBACK COMPLETE
Primary region (europe-west1) is now serving 100% of production traffic.
DR cluster scaled back to baseline.
Post-mortem: TBD within 48h
```

---

## Recovery Time Objectives

| Scenario | RTO | Notes |
|---|---|---|
| Traffic shifted to DR | < 5 min | Multi-cluster Ingress re-routes automatically |
| Stateless workloads | < 5 min | Already running in DR |
| Stateful (Cloud Spanner) | < 1 min RPO | Multi-region by default |
| Stateful (Cloud SQL) | < 15 min | Cross-region replica promotion |

---

## Post-Mortem Requirements

A post-mortem is **mandatory** for every regional failover. It must include:

- Timeline of events (detection → declaration → failover → failback)
- Root cause analysis
- User impact assessment
- Preventive actions with owners and due dates

File the post-mortem within 48 hours using `docs/postmortem-template.md`.

---

*Last updated: February 2026*
