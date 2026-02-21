# Runbook: Node Not Ready

**Severity:** P2 (single node) | P1 (multiple nodes or entire zone)
**Alert:** `GKE Node Not Ready`

---

## Symptoms

- Node shows `STATUS = NotReady` in `kubectl get nodes`
- Pods on the node stuck in `Unknown` or `Terminating` state
- Services losing endpoints as pods are evicted

---

## Diagnosis

```bash
# 1. Check overall node status
kubectl get nodes -o wide

# 2. Get recent events and conditions for the affected node
kubectl describe node <node-name> | tail -40

# 3. Check specific conditions
kubectl get node <node-name> -o jsonpath='{.status.conditions[*]}'

# 4. Check if GKE auto-repair or autoscaler is already acting
kubectl get events --field-selector involvedObject.name=<node-name> --sort-by='.lastTimestamp'

# 5. Check kubelet logs via Cloud Logging
gcloud logging read \
  'resource.type="k8s_node" AND resource.labels.node_name="NODE_NAME"' \
  --limit=50 --format=json
```

### Common Conditions to Look For

| Condition | Meaning |
|---|---|
| `KubeletNotReady` | kubelet stopped reporting to API server |
| `DiskPressure` | Node disk is full or near full |
| `MemoryPressure` | Node is OOM or near OOM |
| `NetworkUnavailable` | CNI plugin issue |

---

## Resolution

### Option A: Wait for GKE Auto-Repair (preferred)

GKE node auto-repair detects unresponsive nodes and triggers replacement automatically. **No action needed** if the node recovers or is replaced within 10 minutes.

Check if auto-repair is in progress:

```bash
gcloud container operations list \
  --filter="targetLink~CLUSTER_NAME AND status=RUNNING" \
  --region=REGION
```

### Option B: Manual Cordon and Drain

If the node is not recovering and pods need to be moved immediately:

```bash
# 1. Cordon — prevent new pods from scheduling on the node
kubectl cordon <node-name>

# 2. Drain — evict all pods gracefully
kubectl drain <node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=60 \
  --timeout=5m

# 3. Delete the node — GCE will replace it automatically
kubectl delete node <node-name>

# 4. Watch for replacement
kubectl get nodes -w
```

### Option C: Entire Zone or Node Pool Unhealthy

```bash
# Check which zone nodes are in
kubectl get nodes -L topology.kubernetes.io/zone

# If a zone is experiencing outage, check GCP status dashboard
# https://status.cloud.google.com

# If zone outage confirmed, initiate regional failover
# See: runbooks/dr-failover.md
```

---

## Post-Incident Checks

```bash
# Verify no pods remain stuck in Terminating
kubectl get pods -A | grep -v Running | grep -v Completed

# Confirm auto-repair triggered in logs
gcloud logging read \
  'logName="projects/PROJECT/logs/cloudaudit.googleapis.com%2Factivity" AND protoPayload.methodName="google.container.v1.ClusterManager.SetNodePoolManagement"' \
  --limit=5

# Check node pool health
gcloud container node-pools describe POOL_NAME \
  --cluster=CLUSTER_NAME \
  --region=REGION
```

> **Post-mortem required** if the outage affected production traffic for more than 10 minutes.

---

*Last updated: February 2026*
