# Runbook: Certificate Rotation

**Severity:** P2 (cert expired or < 7 days to expiry) | P3 (renewal failed, > 7 days remaining)

> ℹ️ cert-manager auto-renews certificates 30 days before expiry. This runbook is for cases where auto-renewal fails or manual rotation is required.

---

## Check Certificate Status

```bash
# List all certificates and their expiry / ready state
kubectl get certificate -A

# Get detailed status for a specific certificate
kubectl describe certificate <cert-name> -n <namespace>

# Check the underlying secret to see actual expiry date
kubectl get secret <tls-secret-name> -n <namespace> \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates
```

**Healthy output** — `READY=True`, expiry > 30 days away.

**Problem output** — `READY=False`, or expiry < 7 days.

---

## Diagnose Renewal Failure

```bash
# 1. Check the Certificate resource status and events
kubectl describe certificate <cert-name> -n <namespace>

# 2. Check the associated CertificateRequest
kubectl get certificaterequest -n <namespace>
kubectl describe certificaterequest <cr-name> -n <namespace>

# 3. Check the Order (ACME) or Request (CA)
kubectl get order -n <namespace>
kubectl describe order <order-name> -n <namespace>

# 4. Check cert-manager controller logs for errors
kubectl logs -n cert-manager deploy/cert-manager --tail=100

# 5. Check the ClusterIssuer status
kubectl describe clusterissuer letsencrypt-prod
```

### Common Failure Causes

| Error in logs | Cause | Fix |
|---|---|---|
| `ACME: rate limit exceeded` | Too many requests to Let's Encrypt | Wait 1 hour. Switch to staging issuer for testing. |
| `DNS record not found` | Cloud DNS propagation delay | Wait 5 min and retry, or check DNS API permissions |
| `Connection refused` | cert-manager can't reach ACME server | Check cluster egress / NetworkPolicy |
| `Unauthorized` | Cloud DNS IAM permission missing | Grant `roles/dns.admin` to cert-manager GSA |
| `Context deadline exceeded` | Webhook timeout | Restart cert-manager webhook: `kubectl rollout restart deploy/cert-manager-webhook -n cert-manager` |

---

## Force Manual Renewal

If cert-manager is not renewing automatically, force a new attempt:

```bash
# Delete the certificate — cert-manager recreates it immediately
kubectl delete certificate <cert-name> -n <namespace>

# Watch cert-manager create a new CertificateRequest
kubectl get certificaterequest -n <namespace> -w

# Watch the Certificate become Ready
kubectl get certificate <cert-name> -n <namespace> -w
```

---

## Emergency: Certificate Already Expired

If a certificate has already expired and is causing `SSL_ERROR` for users:

```bash
# 1. Check if there's a valid cert in staging/backup
kubectl get secret -n <namespace> | grep tls

# 2. If cert-manager renewal is stuck, delete the stuck Order
kubectl delete order -n <namespace> <order-name>

# 3. Delete and recreate the Certificate to force a clean renewal
kubectl delete certificate <cert-name> -n <namespace>
# cert-manager will immediately create a new CertificateRequest

# 4. If Let's Encrypt rate-limited, switch temporarily to staging issuer
# Edit the Certificate to reference letsencrypt-staging
# Once renewed, switch back to letsencrypt-prod

# 5. Monitor renewal
kubectl describe certificate <cert-name> -n <namespace>
kubectl get events -n <namespace> --field-selector reason=Issued
```

---

## Rotate KMS Keys (Platform Certificates)

KMS keys used for etcd encryption and Binary Authorization rotate automatically every 90 days. To trigger a manual rotation:

```bash
# Rotate a KMS key version
gcloud kms keys versions create \
  --key=CLUSTER_NAME-etcd-key \
  --keyring=CLUSTER_NAME-keyring \
  --location=REGION

# Verify new version is available
gcloud kms keys versions list \
  --key=CLUSTER_NAME-etcd-key \
  --keyring=CLUSTER_NAME-keyring \
  --location=REGION

# GKE will re-encrypt etcd using the new key version automatically
```

---

## Post-Rotation Verification

```bash
# Verify all certificates are Ready
kubectl get certificate -A | grep -v True

# Verify TLS is working end-to-end
curl -v https://api.payments.example.com/health 2>&1 | grep -E "SSL|expire|issuer"

# Check cert-manager metrics (renewals in last 24h)
# In Grafana: cert-manager dashboard → Certificates panel
```

---

*Last updated: February 2026*
