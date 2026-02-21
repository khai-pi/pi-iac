# Runbook: Incident Response

> Step-by-step guide for declaring, managing, and resolving production incidents on the GKE platform.

---

## Incident Severity Levels

| Severity | Definition | Examples | Response SLA |
|---|---|---|---|
| **P1** | Complete service outage or data integrity risk | API server down, region failover triggered, data exfiltration | Page immediately — 5 min response, 24/7 |
| **P2** | Significant degradation affecting users | Node NotReady, certificate expired, >10% error rate | Page on-call — 30 min response, 24/7 |
| **P3** | Minor degradation, workaround available | HPA at max replicas, quota >80%, single pod restarting | Ticket — resolve within 4 hours (business hours) |
| **P4** | No user impact, technical debt | Deprecated API usage, config drift detected | Ticket — resolve within sprint |

---

## Escalation Path

| Level | Who | How to Reach | Response Time |
|---|---|---|---|
| L1 | On-call engineer | PagerDuty auto-page | Immediate |
| L2 | Platform lead | PagerDuty escalation (15 min no response) | 15 min (P1) |
| L3 | GCP Support | [support.google.com](https://support.google.com) — open P1 case | 1 hour (P1) |
| L4 | Engineering Director | Direct Slack DM | Business hours only |

---

## Incident Lifecycle

### 1. Detect

Incidents are detected via:
- PagerDuty alert from Cloud Monitoring
- User report in `#incidents-prod`
- On-call engineer notices anomaly

### 2. Declare

If you confirm an incident, immediately:

```
Post in #incidents-prod:

🚨 INCIDENT DECLARED — [P1/P2]
Service: [what is affected]
Impact: [describe user impact]
IC: [@your-name]
Bridge: [Zoom link]
```

### 3. Investigate

```bash
# Check cluster health
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed

# Check recent events
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Check ArgoCD for any recent deployments (possible cause)
argocd app list
argocd app history <app-name>

# Check Cloud Monitoring for anomalies
# https://console.cloud.google.com/monitoring

# Check GCP Status for regional issues
# https://status.cloud.google.com
```

### 4. Communicate

Post updates in `#incidents-prod` **every 15 minutes** using this template:

```
[HH:MM UTC] Status: Investigating | Identified | Mitigating | Resolved
Impact: [current impact description]
Actions taken: [what you've done]
Next update: [HH:MM UTC]
```

### 5. Mitigate

Apply the fastest fix that restores service, even if it's not the root cause fix:

```bash
# Rollback a bad deployment
kubectl rollout undo deployment/<n> -n <namespace>

# Scale up replicas to absorb load
kubectl scale deployment/<n> -n <namespace> --replicas=10

# Redirect traffic to DR cluster
# See: runbooks/dr-failover.md

# Restart a stuck component
kubectl rollout restart deployment/<n> -n <namespace>
```

### 6. Resolve

Once service is restored:

```
Post in #incidents-prod:

✅ INCIDENT RESOLVED — [P1/P2]
Duration: [HH:MM – HH:MM UTC] (~X minutes)
Root cause: [brief description]
Fix applied: [what was done]
Post-mortem: [link or "TBD within 48h"]
```

### 7. Post-Mortem

**Required for:** all P1 incidents, P2 incidents lasting >30 minutes.

Post-mortem must be filed within 48 hours. Use the template at `docs/postmortem-template.md`.

---

## Useful Commands During an Incident

```bash
# Get cluster-wide resource usage
kubectl top nodes
kubectl top pods -A --sort-by=memory | head -20

# Check all non-running pods
kubectl get pods -A | grep -v -E 'Running|Completed|Succeeded'

# Get recent cluster events
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# Check HPA status (is autoscaling maxed out?)
kubectl get hpa -A

# Check PodDisruptionBudgets (might be blocking drains)
kubectl get pdb -A

# Force-restart a deployment without changing anything
kubectl rollout restart deployment/<n> -n <namespace>

# Check if ArgoCD has pending syncs or errors
argocd app list | grep -v Synced

# Check cert expiry
kubectl get certificate -A

# Check if external secrets are syncing
kubectl get externalsecret -A | grep -v True
```

---

## Common Incident Patterns

| Symptom | Likely Cause | Quick Fix |
|---|---|---|
| All pods in namespace `Pending` | ResourceQuota exhausted | Scale down or delete old pods |
| `ImagePullBackOff` across multiple services | Artifact Registry issue or node SA permissions | Check `kubectl describe pod` for exact error |
| Sudden spike in 5xx errors after deployment | Bad release | `kubectl rollout undo deployment/<n>` |
| Nodes all `NotReady` in one zone | GCP zone outage | Initiate DR failover |
| cert-manager pods crashing | Webhook issue | `kubectl rollout restart deploy/cert-manager -n cert-manager` |
| ArgoCD not syncing | Git credentials or network issue | Check ArgoCD logs |

---

*Last updated: February 2026*
