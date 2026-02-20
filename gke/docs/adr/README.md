# Architecture Decision Records

Architecture Decision Records (ADRs) document significant technical decisions made during the design and evolution of the Enterprise GKE platform. Each ADR captures the context, the options considered, the decision made, and its consequences.

## Index

| ADR | Title | Status | Date |
|---|---|---|---|
| [ADR-001](adr-001-shared-vpc.md) | Use Shared VPC over per-project VPCs | Accepted | 2025-06 |
| [ADR-002](adr-002-gke-standard-vs-autopilot.md) | Use GKE Standard over GKE Autopilot | Accepted | 2025-06 |
| [ADR-003](adr-003-argocd-vs-flux.md) | Use ArgoCD over Flux for GitOps | Accepted | 2025-07 |
| [ADR-004](adr-004-workload-identity.md) | Enforce Workload Identity — no SA keys allowed | Accepted | 2025-07 |
| [ADR-005](adr-005-external-secrets.md) | Use External Secrets Operator with Secret Manager | Accepted | 2025-08 |
| [ADR-006](adr-006-multi-region.md) | Active/active multi-region with Multi-cluster Ingress | Accepted | 2025-09 |

## ADR Lifecycle

- **Proposed** — under discussion
- **Accepted** — decision made and implemented
- **Deprecated** — superseded by a newer ADR
- **Superseded** — replaced by ADR-XXX

## Creating a New ADR

Copy `adr-template.md` and increment the number. Raise a PR for team review before marking as Accepted.
