# ADR-005: Use External Secrets Operator with Secret Manager

**Status:** Accepted
**Date:** 2025-08-04
**Authors:** Platform Engineering Team, Security Team
**Deciders:** CISO, Platform Lead

---

## Context

Applications need access to secrets (database passwords, API keys, tokens). These secrets must be stored securely and injected into pods at runtime. We evaluated how to bridge Secret Manager (where secrets live) with Kubernetes (where applications run).

---

## Options Considered

### Option 1: Store Secrets in Kubernetes Secrets Directly

Teams create Kubernetes Secrets manually or via CI pipelines using `kubectl create secret`. Secrets are stored in etcd.

**Pros:**
- Native Kubernetes — no additional tooling
- Simple for developers

**Cons:**
- Kubernetes Secrets are base64-encoded, not encrypted, by default in etcd
- Even with etcd CMEK (which we have), secrets are replicated across API server memory
- No single source of truth — secrets live in etcd AND (potentially) in CI/CD systems
- Secret rotation requires re-running CI pipeline and restarting pods
- No audit trail of which pod accessed which secret
- Secrets in GitOps repos (even encrypted) create a second credential to manage

### Option 2: Vault (HashiCorp)

Run Vault (self-hosted or HCP Vault) as the secrets backend. Use the Vault Agent or CSI provider to inject secrets into pods.

**Pros:**
- Powerful — dynamic secrets, lease-based access, fine-grained policies
- Vault Agent auto-renews secrets in running pods (no pod restart needed)
- Strong audit log

**Cons:**
- Requires running and operating Vault as a highly available, persistent service
- Vault is itself a secret — its unseal keys must be secured
- Adds significant operational complexity and cost
- We already pay for Secret Manager (included in GCP)
- Another system to patch, upgrade, and on-call for

### Option 3: External Secrets Operator (ESO) + Secret Manager

ESO is a Kubernetes operator that syncs secrets from external providers (Secret Manager, Vault, AWS SSM, etc.) into Kubernetes Secrets. It polls Secret Manager and keeps the Kubernetes Secret up to date.

**Pros:**
- Secret Manager is the single source of truth — no secrets in etcd by default
- Works with Workload Identity — no additional credentials for ESO itself
- Automatic sync — rotating a secret in Secret Manager propagates to pods on the next sync cycle
- `ExternalSecret` manifests are safe to store in Git (they reference secrets, not contain them)
- Supports multiple backends — future migration to Vault would only require changing the `ClusterSecretStore`
- Low operational overhead — ESO runs as a small deployment, not a stateful service
- Strong adoption, CNCF Sandbox project

**Cons:**
- Secrets still temporarily exist as Kubernetes Secrets in etcd (during the sync window)
- Additional CRD-based API for developers to learn
- Sync latency — changes in Secret Manager take up to `refreshInterval` to reach pods

---

## Decision

**Use External Secrets Operator (ESO) with Google Secret Manager (Option 3).**

Secret Manager + ESO provides the best balance of security and operational simplicity for a GCP-native platform. The alternative of running Vault adds a significant operational burden with minimal additional security benefit over Secret Manager + etcd CMEK.

The Kubernetes Secrets that ESO creates in etcd are protected by etcd CMEK (ADR-002), mitigating the risk of the temporary in-cluster storage.

---

## Consequences

**Positive:**
- Single source of truth for all secrets in Secret Manager
- Secret rotation: update in Secret Manager → ESO syncs → pods restart (or live-reload if app supports it)
- `ExternalSecret` CRs are safe to commit to the GitOps repo — no secret values in Git
- ESO authenticates to Secret Manager via Workload Identity — no additional credentials
- Per-secret access control in Secret Manager IAM

**Negative:**
- Secrets exist briefly as Kubernetes Secrets in etcd (protected by CMEK)
- Developers must understand the `ExternalSecret` / `ClusterSecretStore` CRD model
- ESO must be highly available — if it fails, secrets don't sync (existing Kubernetes Secrets remain valid; only rotation/creation of new secrets is blocked)

**Operational notes:**
- ESO is deployed in the `external-secrets` namespace on the `system-pool`
- `ClusterSecretStore` is configured cluster-wide using ESO's Workload Identity
- Default `refreshInterval` is 1 hour; set to shorter for sensitive secrets that rotate frequently
- ESO health is monitored via Managed Prometheus and Grafana

---

*Related: [ADR-004](adr-004-workload-identity.md)*
