# Security & Compliance Guide

> Zero-trust security architecture for the Enterprise GKE platform.

---

## Table of Contents

- [Security Principles](#security-principles)
- [Identity & Access Management](#identity--access-management)
- [Image Supply Chain](#image-supply-chain)
- [Pod & Container Security](#pod--container-security)
- [Network Security](#network-security)
- [Secrets Management](#secrets-management)
- [Audit Logging](#audit-logging)
- [Compliance Checklist](#compliance-checklist)
- [Incident Response](#incident-response)

---

## Security Principles

### Zero Trust

No component is trusted by default — not even components inside the cluster. Every service authenticates, every connection is encrypted, every action is authorized.

- Workload Identity replaces service account keys — no credentials on disk, ever
- mTLS via Anthos Service Mesh — all pod-to-pod traffic is mutually authenticated
- NetworkPolicies are default-deny — every connection must be explicitly allowed
- RBAC is additive — no broad cluster-level roles for application teams

### Defense in Depth

| Layer | Control | Protects Against |
|---|---|---|
| Edge | Cloud Armor WAF + DDoS | XSS, SQLi, LFI, volumetric DDoS |
| Network | VPC Service Controls | Data exfiltration from GCP services |
| Node | Shielded VMs + COS | Boot-time rootkit, kernel exploit |
| Runtime | seccomp + AppArmor | Syscall-level exploits, container escape |
| Application | Pod Security Standards | Privilege escalation, host namespace access |
| Data | etcd CMEK + Secret Manager | Data theft from etcd or GCS |
| Supply chain | Binary Authorization | Unsigned or malicious image deployment |

---

## Identity & Access Management

### Human Access

All human access is brokered through Google Identity. There are no local Kubernetes users, no embedded kubeconfig credentials, and no shared service account keys for humans.

- Developers authenticate with `gcloud auth login` using their `@example.com` identity
- Cluster-admin access is restricted to the platform team Google Group
- Break-glass access requires a separate privileged GCP project + MFA re-authentication and triggers an immediate SIEM alert
- All `kubectl` commands are audited via Kubernetes Audit Logs to Cloud Logging

### Workload Identity

Pods access GCP services via Workload Identity — no service account key files anywhere.

```
Pod (with KSA annotation)
  → GKE projects short-lived token automatically
  → GCP API authenticates token as the linked GSA
  → Token rotates every hour automatically
```

**Setup (done via Terraform — reference only):**

```bash
# Bind KSA to GSA
gcloud iam service-accounts add-iam-policy-binding GSA_EMAIL \
  --role=roles/iam.workloadIdentityUser \
  --member="serviceAccount:PROJECT.svc.id.goog[NAMESPACE/KSA_NAME]"
```

```yaml
# Kubernetes Service Account annotation
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app-ksa
  namespace: team-payments
  annotations:
    iam.gke.io/gcp-service-account: my-app-gsa@PROJECT.iam.gserviceaccount.com
```

### IAM Standard Roles

| Role | Granted To |
|---|---|
| `roles/secretmanager.secretAccessor` | Team GSAs (specific secrets only) |
| `roles/cloudtrace.agent` | All team GSAs |
| `roles/monitoring.metricWriter` | All team GSAs |
| `roles/logging.logWriter` | GKE node SA only |
| `roles/artifactregistry.reader` | GKE node SA only |
| `roles/container.admin` | Platform team GSA only |

> **Policy:** Requests for roles outside this list must be submitted via GitHub Issues with business justification and approved by the platform lead and security lead.

---

## Image Supply Chain

Every image that runs in production must trace a verifiable path from source code to running container. Binary Authorization enforces this at admission.

### Stages

| # | Stage | Details |
|---|---|---|
| 1 | Source commit | Developer pushes signed commits (GitHub Vigilant Mode required) |
| 2 | CI pipeline | Cloud Build triggers on merge; SLSA provenance generated |
| 3 | Build & sign | Image built and signed with KMS-backed attestor via cosign |
| 4 | Vulnerability scan | Container Analysis scans; blocks on CRITICAL CVEs |
| 5 | Push to registry | Artifact Registry, immutable SHA digest |
| 6 | Admission control | Binary Authorization verifies attestation before pod starts |
| 7 | Runtime | Pod runs with seccomp, read-only FS, dropped capabilities |

### Binary Authorization Policy

```yaml
defaultAdmissionRule:
  evaluationMode: REQUIRE_ATTESTATION
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
  requireAttestationsBy:
  - projects/PROJECT/attestors/build-verified

# Allow GKE system images without attestation
clusterAdmissionRules:
  europe-west1.prod-cluster-primary:
    evaluationMode: ALWAYS_ALLOW
    enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
```

> Dev and staging use `DRYRUN_AUDIT_LOG_ONLY` — blocks are logged but not enforced, allowing iteration without friction.

---

## Pod & Container Security

### Pod Security Standards

All namespaces enforce the Kubernetes `restricted` Pod Security Standard via namespace labels:

```yaml
metadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### Required Security Fields

Every container must include:

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: [ALL]
```

### Workload Security Checklist

| Requirement | Enforced | Mechanism |
|---|---|---|
| `runAsNonRoot: true` | ✅ Yes | Pod Security Standards |
| `allowPrivilegeEscalation: false` | ✅ Yes | Pod Security Standards |
| `capabilities.drop: [ALL]` | ✅ Yes | Pod Security Standards |
| `seccompProfile: RuntimeDefault` | ✅ Yes | Pod Security Standards |
| `readOnlyRootFilesystem: true` | ⚠️ Recommended | PSS warn mode |
| `resources.requests` and `limits` set | ✅ Yes | LimitRange |
| No `hostPID`, `hostNetwork`, `hostIPC` | ✅ Yes | Pod Security Standards |
| No privileged containers | ✅ Yes | Pod Security Standards |
| Image uses SHA digest (not mutable tag) | ⚠️ Recommended | CI policy check |
| Liveness and readiness probes set | ⚠️ Recommended | CI policy check |

---

## Network Security

### Cloud Armor WAF

All external traffic passes through Cloud Armor before reaching GKE.

| Rule | Priority | Action |
|---|---|---|
| IP allowlist | 1000 | ALLOW — configurable per environment |
| OWASP XSS (v33) | 2000 | DENY 403 |
| OWASP SQLi (v33) | 2001 | DENY 403 |
| OWASP LFI (v33) | 2002 | DENY 403 |
| OWASP RFI (v33) | 2003 | DENY 403 |
| Rate limit (per IP) | 3000 | THROTTLE — 1000 req/min, DENY 429 above |
| Adaptive Protection | Auto | ML-based DDoS auto-blocking |
| Default rule | 65534 | DENY 403 — explicit allow required |

### Anthos Service Mesh (mTLS)

All pod-to-pod communication uses mutual TLS in `STRICT` mode — plain text connections are rejected.

- Every pod gets an Envoy sidecar proxy injected automatically
- Service identity is based on the Kubernetes Service Account (SPIFFE/SVID)
- Certificates rotate automatically every 24 hours
- Traffic policies (retries, timeouts, circuit breaking) managed via `VirtualService` and `DestinationRule`

### NetworkPolicy

All namespaces start with a default-deny policy:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
```

Allowed traffic is added with explicit policies. DNS egress and same-namespace traffic are allowed by platform defaults.

---

## Secrets Management

> **Policy:** Secrets are NEVER stored in Git, Kubernetes manifests, container images, env files, or Terraform state. All secrets live exclusively in Secret Manager.

### Storage Tiers

| Data Type | Storage | Access Method |
|---|---|---|
| Passwords, API keys, tokens | Secret Manager | ESO `ExternalSecret` → K8s Secret → env var |
| TLS certificates | cert-manager + GCP CAS | Auto-mounted K8s Secret |
| Feature flags, app config | ConfigMap (in Git) | Env var or volume mount |
| GCP service credentials | Workload Identity | Automatic projected token — no secret needed |

### Rotation Policy

| Secret Type | Frequency | Owner |
|---|---|---|
| Database passwords | Quarterly (90 days) | Application team |
| External API keys | Annually or on exposure | Application team |
| KMS encryption keys | Auto every 90 days | Platform team (automated) |
| TLS certificates | Auto 30 days before expiry | Platform team (cert-manager) |
| ArgoCD admin password | Quarterly | Platform team |
| Grafana admin password | Quarterly | Platform team |

---

## Audit Logging

All actions on the platform are captured and retained for 2 years in Cloud Logging.

**Active log sources:**

- **Kubernetes Audit Logs** — every API server request (create, update, delete, get)
- **Cloud Audit Logs** — all GCP API calls (IAM changes, Secret Manager access, KMS operations)
- **VPC Flow Logs** — network traffic metadata for all subnets (50% sample)
- **Cloud Armor Logs** — WAF decisions, blocked requests, rate limit events
- **Binary Authorization Logs** — all admission decisions with image details

### Security Alerts

| Alert | Severity | Destination |
|---|---|---|
| Binary Authorization image blocked | P2 | PagerDuty + #security |
| Break-glass access used | P1 | PagerDuty + CISO email |
| Service account key created | P1 | PagerDuty (policy violation) |
| Org policy violated | P2 | #security |
| Pod security violation | P3 | #security |
| Unusual data access (SCC) | P2 | #security |
| Network policy denied traffic | P4 | Log-based metric only |

---

## Compliance Checklist

Reviewed quarterly by the platform team and security team.

### Cluster Controls

| Control | Status |
|---|---|
| Private cluster — no public node IPs | ✅ PASS |
| Workload Identity enabled on all clusters | ✅ PASS |
| etcd encrypted with CMEK (KMS) | ✅ PASS |
| Binary Authorization enforced in production | ✅ PASS |
| Shielded nodes — Secure Boot + Integrity Monitoring | ✅ PASS |
| Org policy: no SA key creation | ✅ PASS |
| mTLS enforced via Anthos Service Mesh (STRICT) | ✅ PASS |
| Vulnerability scanning enabled in Artifact Registry | ✅ PASS |
| Cloud Armor WAF active on all external ingress | ✅ PASS |
| Kubernetes Audit Logs enabled | ✅ PASS |
| VPC Flow Logs enabled | ✅ PASS |
| All secrets in Secret Manager (none in etcd) | ✅ PASS |

---

## Incident Response

### Incident Classification

| Class | Examples | Initial Response |
|---|---|---|
| Critical | Container escape, cluster compromise, data exfiltration | Isolate affected nodes immediately. Page on-call + CISO. |
| High | Unauthorized access, malicious image deployed, secret leaked | Rotate affected credentials. Page on-call. Security review. |
| Medium | Policy violation, unusual access, failed Binary Auth | Investigate root cause. Notify security team. |
| Low | Deprecated API usage, misconfiguration (no exploitation) | Create remediation ticket. Fix within sprint. |

### Isolating a Compromised Pod

```bash
# 1. Preserve forensic evidence BEFORE deleting
# Cordon the node to prevent new scheduling
kubectl cordon <node-name>

# 2. Snapshot node disk via GCP Console for forensics

# 3. Revoke the pod's service account IAM permissions immediately
gcloud projects remove-iam-policy-binding PROJECT \
  --member="serviceAccount:GSA_EMAIL" \
  --role="roles/ROLE"

# 4. Delete the pod AFTER forensic collection
kubectl delete pod <pod-name> -n <namespace>

# 5. Rotate all secrets the pod had access to
# See: runbooks/secret-rotation.md
```

> **After any security incident:** rotate all affected secrets, file a Security Incident Report within 24 hours, and schedule a post-mortem.

---

*Document Owner: Security Team + Platform Engineering | Review Cycle: Quarterly | Classification: CONFIDENTIAL*
