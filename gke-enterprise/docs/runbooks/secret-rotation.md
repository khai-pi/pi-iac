# Runbook: Secret Rotation

**Severity:** P2 (secret known to be compromised) | P3 (scheduled rotation)

> ⚠️ **If a secret is known to be compromised, treat this as a security incident. Follow `runbooks/incident-response.md` in parallel.**

---

## When to Rotate

| Trigger | Action Required |
|---|---|
| Scheduled rotation (quarterly) | Standard rotation procedure below |
| Secret leaked in Git or logs | Immediate rotation — treat as P2 incident |
| Employee offboarding | Rotate any secrets the person had access to |
| Suspected breach | Immediate rotation + security incident |
| Secret Manager audit shows unexpected access | Investigate + rotate |

---

## Standard Rotation Procedure

### 1. Create a New Secret Version

```bash
# Option A: from a value
echo -n "NEW_SECRET_VALUE" | \
  gcloud secrets versions add SECRET_NAME \
    --data-file=- \
    --project=PROJECT_ID

# Option B: from a file
gcloud secrets versions add SECRET_NAME \
  --data-file=/path/to/secret.txt \
  --project=PROJECT_ID

# Verify the new version was created
gcloud secrets versions list SECRET_NAME --project=PROJECT_ID
```

### 2. Test the New Secret (before deploying)

Verify the new value works against the target system (database, API, etc.) before rotating in production. Use a staging environment or a test connection.

### 3. Force External Secrets Operator to Sync

ESO polls Secret Manager on the `refreshInterval` (default: 1 hour). Force immediate sync:

```bash
# Annotate the ExternalSecret to trigger immediate refresh
kubectl annotate externalsecret <es-name> -n <namespace> \
  force-sync=$(date +%s) --overwrite

# Verify the Kubernetes Secret was updated
# (check resourceVersion changed)
kubectl get secret <secret-name> -n <namespace> \
  -o jsonpath='{.metadata.resourceVersion}'

# Verify ESO sync status
kubectl describe externalsecret <es-name> -n <namespace>
```

### 4. Rollout Restart Affected Workloads

Pods only read secrets at startup. Trigger a rolling restart:

```bash
# Restart all deployments that use this secret
kubectl rollout restart deployment/<n> -n <namespace>

# Monitor rollout
kubectl rollout status deployment/<n> -n <namespace>

# Verify pods are healthy
kubectl get pods -n <namespace> -l app=<app-name>
```

### 5. Verify the Rotation Worked

```bash
# Confirm the application is using the new secret
# (application-specific — check health endpoint or logs)
kubectl logs -n <namespace> deploy/<n> --tail=20

# Check error rate is still baseline in Grafana
```

### 6. Disable the Old Secret Version

Do **not delete** — keep for rollback if needed.

```bash
# Get the old version number
gcloud secrets versions list SECRET_NAME --project=PROJECT_ID

# Disable (not delete) the old version
gcloud secrets versions disable OLD_VERSION_NUMBER \
  --secret=SECRET_NAME \
  --project=PROJECT_ID
```

---

## Rollback: New Secret is Invalid

If the new secret causes errors:

```bash
# 1. Re-enable the old secret version
gcloud secrets versions enable OLD_VERSION_NUMBER \
  --secret=SECRET_NAME \
  --project=PROJECT_ID

# 2. Disable the new broken version
gcloud secrets versions disable NEW_VERSION_NUMBER \
  --secret=SECRET_NAME \
  --project=PROJECT_ID

# 3. Force ESO to sync back to old version
kubectl annotate externalsecret <es-name> -n <namespace> \
  force-sync=$(date +%s) --overwrite

# 4. Rollout restart
kubectl rollout restart deployment/<n> -n <namespace>
```

---

## Emergency Rotation (Secret Compromised)

If a secret has been leaked or accessed by an unauthorized party:

```bash
# 1. Immediately revoke access at the source
# (rotate the DB password at the database level, revoke the API key, etc.)

# 2. Create new secret version with the new value
echo -n "NEW_SAFE_VALUE" | \
  gcloud secrets versions add SECRET_NAME --data-file=-

# 3. Force sync and rollout restart (as above)

# 4. Disable ALL previous versions
gcloud secrets versions list SECRET_NAME --format="value(name)" | \
  grep -v "^1$" | \
  xargs -I{} gcloud secrets versions disable {} --secret=SECRET_NAME

# 5. Audit Secret Manager access logs for the compromised secret
gcloud logging read \
  'protoPayload.resourceName~"SECRET_NAME" AND protoPayload.methodName="AccessSecretVersion"' \
  --limit=50 \
  --format=json

# 6. File a security incident report
```

---

## Batch Rotation (Quarterly)

Script for rotating all secrets in a namespace at once (adapt as needed):

```bash
#!/bin/bash
NAMESPACE="team-payments"

echo "Forcing ESO sync for all ExternalSecrets in $NAMESPACE..."
for es in $(kubectl get externalsecret -n $NAMESPACE -o name); do
  kubectl annotate $es -n $NAMESPACE \
    force-sync=$(date +%s) --overwrite
  echo "  Synced: $es"
done

echo "Restarting all deployments in $NAMESPACE..."
kubectl rollout restart deployment -n $NAMESPACE

echo "Waiting for rollouts to complete..."
kubectl rollout status deployment -n $NAMESPACE --timeout=5m

echo "Done. Verify application health before disabling old secret versions."
```

---

*Last updated: February 2026*
