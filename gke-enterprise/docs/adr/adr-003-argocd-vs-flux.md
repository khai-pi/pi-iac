# ADR-003: Use ArgoCD over Flux for GitOps

**Status:** Accepted
**Date:** 2025-07-02
**Authors:** Platform Engineering Team
**Deciders:** Platform Lead, Tech Leads

---

## Context

The platform needs a GitOps engine to continuously reconcile cluster state from Git. The two leading CNCF-graduated options are ArgoCD and Flux. We needed to choose one as the platform standard.

---

## Options Considered

### Option 1: ArgoCD

A declarative GitOps continuous delivery tool with a built-in web UI, RBAC, and multi-cluster support.

**Pros:**
- Rich web UI — non-technical stakeholders can view deployment status
- Built-in RBAC model with SSO support (OIDC/LDAP/Google)
- ApplicationSets allow templated deployment across many clusters and namespaces
- Clear diff visualization before sync
- Rollback UI — one click to revert to any previous revision
- Multi-cluster management from a single ArgoCD instance
- Active community, large adoption, backed by Intuit (and later Akuity)
- Strong audit trail — every sync is logged with actor, timestamp, and diff

**Cons:**
- More resource-intensive than Flux (requires ArgoCD server, repo-server, dex, Redis)
- UI is a potential attack surface (mitigated by internal-only access)
- ApplicationSet controller can be complex to configure correctly

### Option 2: Flux

A GitOps toolkit of composable controllers (source, kustomize, helm, notification).

**Pros:**
- Lightweight — minimal resource footprint
- More composable — use only the controllers you need
- Native support for SOPS encrypted secrets in Git
- CLI-driven (no UI to maintain or secure)
- Excellent Helm controller with fine-grained dependency management

**Cons:**
- No built-in web UI — requires third-party (Weave GitOps) for visualization
- Steeper learning curve for developers unfamiliar with the CRD model
- Multi-cluster support is less polished than ArgoCD's
- Rollback is a manual Git operation (no UI rollback)
- Smaller community than ArgoCD for enterprise use

---

## Decision

**Use ArgoCD (Option 1).**

The web UI and RBAC model are the deciding factors for an enterprise platform serving multiple application teams. Developers need visibility into their deployment status without requiring `kubectl` access. The ApplicationSet feature enables the platform team to template consistent deployment patterns across all teams. The one-click rollback capability reduces MTTR during incidents.

Flux's lower resource footprint was considered but is not material at our scale.

---

## Consequences

**Positive:**
- All teams have visibility into their deployments via the ArgoCD UI
- Platform team can enforce deployment standards via ApplicationSets
- SSO integration means no additional credentials for developers
- Rollback during incidents is fast and accessible to developers (not just platform team)
- Multi-cluster management (primary + DR) from one ArgoCD instance

**Negative:**
- ArgoCD server, repo-server, dex, Redis, and application controller must be maintained
- ArgoCD runs in the `system-pool` to avoid resource competition with application workloads
- UI must be secured (deployed internally only, protected by ASM + IAP)

**Mitigations:**
- ArgoCD deployed with HA (2+ replicas for server and repo-server)
- Access restricted to `internal.example.com` — not exposed to the internet
- Google IAP provides an additional authentication layer in front of ArgoCD

---

*Related: [ADR-002](adr-002-gke-standard-vs-autopilot.md)*
