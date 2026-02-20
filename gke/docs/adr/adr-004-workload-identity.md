# ADR-004: Enforce Workload Identity — No Service Account Keys Allowed

**Status:** Accepted
**Date:** 2025-07-15
**Authors:** Platform Engineering Team, Security Team
**Deciders:** CISO, Platform Lead

---

## Context

Kubernetes workloads frequently need to authenticate to GCP services (Secret Manager, Cloud Storage, BigQuery, Pub/Sub, etc.). Two mechanisms exist: **service account key files** and **Workload Identity**. We needed to establish the platform policy.

---

## Options Considered

### Option 1: Service Account Key Files

Create a GCP service account, download a JSON key file, and mount it as a Kubernetes secret.

**Pros:**
- Simple to understand and implement
- Works in any environment (not GCP-specific)
- No cluster-level configuration required

**Cons:**
- Key files are long-lived credentials (valid until manually revoked)
- Keys can be accidentally committed to Git (has happened at many organizations)
- Keys can be stolen from container images, etcd, or pod memory dumps
- Key rotation is manual, often skipped, and operationally risky
- No audit trail of which pod used a key at what time
- GCP org policies cannot selectively restrict key usage per workload
- Violates zero-trust principles — credentials exist outside the identity system

### Option 2: Workload Identity (GKE Metadata Server)

Pods assume a GCP service account identity via projected Kubernetes service account tokens. The GKE Metadata Server exchanges these tokens for short-lived GCP access tokens automatically.

**Pros:**
- No credentials to manage, rotate, or leak
- Tokens are short-lived (1 hour) and auto-rotate — compromise window is tiny
- Identity is tied to the Kubernetes Service Account — namespaced and auditable
- Access tokens are never written to disk
- GCP audit logs show which workload (KSA) made each API call
- Compatible with all GCP client libraries (no code changes required)
- Org policy can enforce this: `iam.disableServiceAccountKeyCreation = true`

**Cons:**
- Only works on GKE (not portable to non-GCP environments)
- Requires IAM binding between KSA and GSA per workload (automated via Terraform)
- Slightly more complex initial setup

---

## Decision

**Enforce Workload Identity for all workloads. Service account keys are prohibited by org policy.**

The security benefits are non-negotiable. Long-lived key files are the single most common vector for GCP credential compromise. Workload Identity eliminates this entire attack surface with no meaningful developer friction — client libraries pick up credentials automatically.

An org policy (`iam.disableServiceAccountKeyCreation = true`) is applied at the organization level to enforce this technically, not just as a process requirement.

---

## Consequences

**Positive:**
- No credentials to rotate, audit, or accidentally leak
- GCP API access is fully auditable — every call tied to a specific KSA in a specific namespace
- Org policy provides hard technical enforcement (not just documentation)
- Significantly reduces blast radius of a container compromise

**Negative:**
- Applications running outside GKE (local dev, CI runners) cannot use Workload Identity directly
- Developers must use `gcloud auth application-default login` locally (not a production credential)
- Breaking change for any existing workloads using key file secrets — migration required

**Migration for existing workloads:**
1. Create a GSA for the workload if not already existing
2. Create a KSA in the namespace and annotate with the GSA email
3. Bind the KSA to the GSA via `roles/iam.workloadIdentityUser`
4. Update the workload's `serviceAccountName` to the KSA
5. Remove the key file secret and its volume mount
6. Delete the key file from Secret Manager and disable the old SA key

**For local development:**
- Developers use `gcloud auth application-default login` which creates local credentials
- CI pipelines use Workload Identity Federation with GitHub Actions OIDC tokens

---

*Related: [ADR-001](adr-001-shared-vpc.md), [ADR-005](adr-005-external-secrets.md)*
