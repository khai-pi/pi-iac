# Runbook: Pod CrashLoopBackOff

**Severity:** P3 (single pod) | P1 (critical service with zero healthy replicas)
**Alert:** `GKE Pod CrashLoopBackOff`

---

## Symptoms

- Pod `STATUS` shows `CrashLoopBackOff`
- `RESTARTS` counter incrementing rapidly
- Service endpoints missing — no traffic being served
- Dependent services returning 502/503 errors

---

## Diagnosis

```bash
# 1. Find all crashing pods
kubectl get pods -A | grep CrashLoopBackOff

# 2. Get last 100 lines from the crashing container
kubectl logs <pod-name> -n <namespace> --previous --tail=100

# 3. Describe pod — look at Events section and exit code
kubectl describe pod <pod-name> -n <namespace>

# 4. If multi-container pod, target the crashing container
kubectl logs <pod-name> -n <namespace> -c <container-name> --previous
```

### Exit Code Reference

| Exit Code | Likely Cause |
|---|---|
| `1` | Application error — check logs for stack trace |
| `137` | OOMKilled — container exceeded memory limit |
| `139` | Segmentation fault — binary or library crash |
| `143` | SIGTERM not handled — app did not shut down gracefully |
| `2` | Misuse of shell builtins — bad entrypoint command |

```bash
# Get exit code directly
kubectl get pod <pod-name> -n <namespace> \
  -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}'
```

---

## Resolution by Exit Code

### Exit 137 — OOMKilled

```bash
# 1. Check actual memory usage vs limit
kubectl top pod <pod-name> -n <namespace>

# 2. Check how many times the container has been OOMKilled
kubectl get pod <pod-name> -n <namespace> \
  -o jsonpath='{.status.containerStatuses[0].restartCount}'

# 3. Check VPA recommendation for right-sizing
kubectl get vpa <vpa-name> -n <namespace> -o yaml | grep -A5 recommendation

# 4. Temporarily increase memory limit
kubectl set resources deployment <deployment-name> -n <namespace> \
  --limits=memory=2Gi

# 5. Open a PR to update Helm values permanently
```

### Exit 1 — Application Error

```bash
# 1. Check for missing or misconfigured environment variables
kubectl exec <running-pod> -n <namespace> -- env | sort

# 2. Check if ExternalSecrets have synced
kubectl get externalsecret -n <namespace>
kubectl describe externalsecret <name> -n <namespace>

# 3. Verify ConfigMap exists and has expected keys
kubectl get configmap <name> -n <namespace> -o yaml

# 4. Check if the pod can reach its dependencies
kubectl exec <running-pod> -n <namespace> -- \
  wget -qO- http://dependent-service.other-namespace.svc.cluster.local/health
```

### Exit 143 — Graceful Shutdown Issue

```bash
# Check if the app handles SIGTERM
# The container must exit within terminationGracePeriodSeconds (default 30s)
# If it doesn't, it gets SIGKILL (exit 137)

# Increase terminationGracePeriodSeconds if the app needs more time to drain
kubectl patch deployment <name> -n <namespace> --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/terminationGracePeriodSeconds","value":60}]'
```

---

## Escalation: Zero Healthy Replicas

If a critical service has no healthy pods serving traffic:

```bash
# 1. Check how many replicas are available
kubectl get deployment <name> -n <namespace>

# 2. If previous version was working, rollback immediately
kubectl rollout undo deployment/<name> -n <namespace>

# 3. Verify rollback succeeded
kubectl rollout status deployment/<name> -n <namespace>

# 4. Then investigate root cause from the rolled-back state
kubectl logs <new-pod> -n <namespace> --previous
```

---

## Post-Incident Checks

```bash
# Confirm all replicas are Running and Ready
kubectl get pods -n <namespace> -l app=<app-name>

# Verify endpoints are populated (traffic will flow)
kubectl get endpoints <service-name> -n <namespace>

# Check error rate has returned to baseline in Grafana/Cloud Monitoring
```

---

*Last updated: February 2026*
