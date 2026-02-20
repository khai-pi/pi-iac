# Runbook: Cluster Upgrade

**Severity:** Planned maintenance
**Window:** Saturday 02:00–06:00 UTC (default)

> ⚠️ **Never upgrade the control plane and all node pools in the same maintenance window.**
> Control plane first, then node pools one at a time with 24h monitoring between each.

---

## Pre-Upgrade Checklist

- [ ] Read GKE release notes for the target version at [cloud.google.com/kubernetes-engine/docs/release-notes](https://cloud.google.com/kubernetes-engine/docs/release-notes)
- [ ] Check for deprecated APIs used by workloads: `kubectl api-resources`
- [ ] Verify `PodDisruptionBudgets` are set on all stateful workloads
- [ ] Confirm DR cluster is healthy and can receive failover traffic if needed
- [ ] Notify all application teams at least 48 hours in advance via `#platform-announcements`
- [ ] Create a change management ticket and get approval
- [ ] Schedule the maintenance window in GKE console

---

## Step 1: Check Current State

```bash
# Get current control plane version
gcloud container clusters describe CLUSTER_NAME \
  --region=REGION \
  --format="value(currentMasterVersion)"

# Get current node pool versions
gcloud container node-pools list \
  --cluster=CLUSTER_NAME \
  --region=REGION \
  --format="table(name,version)"

# List available versions in the REGULAR channel
gcloud container get-server-config \
  --region=REGION \
  --format="yaml(channels)"
```

---

## Step 2: Upgrade Control Plane

Regional control plane upgrades are zero-downtime — GKE upgrades each zone's master sequentially.

```bash
# Trigger control plane upgrade
gcloud container clusters upgrade CLUSTER_NAME \
  --region=REGION \
  --master \
  --cluster-version=TARGET_VERSION

# Monitor upgrade progress (~10–20 min)
gcloud container operations list \
  --filter="targetLink~CLUSTER_NAME AND status=RUNNING" \
  --region=REGION

# Watch until operation completes
gcloud container operations wait OPERATION_ID --region=REGION
```

**Verify control plane upgrade:**

```bash
kubectl get nodes
kubectl cluster-info
kubectl version --short
```

---

## Step 3: Upgrade Node Pools (one at a time)

Repeat for each node pool. Monitor for 24 hours before proceeding to the next pool.

```bash
# Upgrade a specific node pool
gcloud container node-pools upgrade POOL_NAME \
  --cluster=CLUSTER_NAME \
  --region=REGION

# Monitor pods during the rolling upgrade
# Expect nodes to be cordoned/drained one at a time (surge: +1 node)
kubectl get nodes -w

# Watch for any pods that don't reschedule cleanly
kubectl get pods -A -w | grep -v Running
```

### Upgrade Order (recommended)

1. `system-pool` — platform components, validate ArgoCD/monitoring still work
2. `general-pool` — main application workloads
3. `spot-pool` — spot nodes; pods will be rescheduled automatically
4. `memory-pool` — data/ML workloads; verify jobs resume

---

## Step 4: Post-Upgrade Validation

```bash
# Confirm all nodes are on the new version
kubectl get nodes -o custom-columns="NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion"

# Check no pods are stuck
kubectl get pods -A | grep -v Running | grep -v Completed | grep -v Succeeded

# Run smoke tests for critical services
curl -s https://api.payments.example.com/health | jq .
curl -s https://api.identity.example.com/health | jq .

# Verify ArgoCD is healthy
argocd app list | grep -v Synced

# Check cert-manager is running
kubectl get pods -n cert-manager
```

---

## Post-Upgrade Checklist

- [ ] All nodes show new kubelet version
- [ ] No pods in `CrashLoopBackOff` or `Pending` after 15 minutes
- [ ] Smoke tests passing for all critical services
- [ ] ArgoCD showing all apps as Synced and Healthy
- [ ] Grafana dashboards showing normal error rates and latency
- [ ] Update change management ticket as complete
- [ ] Update internal wiki with new cluster version

---

## Rollback

GKE does not support downgrading the control plane. If issues arise after node pool upgrade:

```bash
# Rollback affected deployments to previous container version
kubectl rollout undo deployment/<name> -n <namespace>

# If node pool is the issue, create a new node pool at the old version
# (requires opening a support case with GCP for control-plane downgrade)
```

> **Prevention:** always upgrade staging 1 week before production and run full regression tests.

---

*Last updated: February 2026*
