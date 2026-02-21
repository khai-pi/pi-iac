# ADR-001: Use Shared VPC over Per-Project VPCs

**Status:** Accepted
**Date:** 2025-06-10
**Authors:** Platform Engineering Team
**Deciders:** CTO, Platform Lead, Security Lead

---

## Context

The platform needs to provide networking for multiple GKE clusters across multiple projects (cluster project, team projects, shared services). We needed to decide whether each project gets its own VPC or whether we use a single Shared VPC hosted in a dedicated host project.

Three options were evaluated.

---

## Options Considered

### Option 1: Per-project VPCs

Each project creates its own VPC with its own subnets. Projects communicate over VPC Peering or via internal load balancers.

**Pros:**
- Simpler to reason about in isolation
- Full team autonomy over their networking

**Cons:**
- VPC Peering does not allow transitive routing — every pair of VPCs requires its own peering
- Duplicate subnets, Cloud NAT, Cloud Routers across every project (cost and operational overhead)
- Firewall rules are decentralized — hard to audit and enforce consistently
- VPC Peering has a hard limit of 25 peers per VPC

### Option 2: Shared VPC

One host project owns the VPC, subnets, Cloud NAT, and firewalls. Service projects attach to it and deploy resources into shared subnets.

**Pros:**
- Single network control plane — one place for firewall rules, NAT, routing
- Central visibility over all traffic (VPC Flow Logs in one place)
- Network team can enforce policy without depending on individual project owners
- No peering limits
- Subnets can be scoped to specific service projects for isolation

**Cons:**
- Requires cross-project IAM bindings for Compute resources
- Network changes require coordination with the platform team (not fully self-service)
- More complex initial Terraform setup

### Option 3: VPC Service Controls only (no Shared VPC)

Use per-project VPCs but add VPC Service Controls to restrict data exfiltration.

**Pros:**
- Strong data exfiltration protection

**Cons:**
- Does not solve the connectivity or operational overhead problems
- Complements but does not replace Shared VPC

---

## Decision

**Use Shared VPC (Option 2).**

The central control plane, unified firewall management, and single point for traffic visibility outweigh the added IAM complexity. The limitation of requiring platform team involvement for network changes is acceptable — application teams should not be modifying network-level constructs directly.

---

## Consequences

**Positive:**
- All firewall rules are in one place — security audits are straightforward
- VPC Flow Logs aggregated in one project
- Cloud NAT and Cloud Router are not duplicated across projects
- Subnet CIDR planning is done once and centrally
- Simplifies compliance scope (network controls owned by one team)

**Negative:**
- Platform team is a dependency for any subnet or firewall rule changes
- Cross-project IAM bindings must be maintained (automated via Terraform)
- Accidental change to the host project could affect all service projects — access to the host project is tightly restricted

**Mitigations:**
- Shared VPC host project has strict IAM — only the platform team service account and platform leads have edit access
- All changes go through Terraform with PR review
- Subnet changes for a single team do not affect other teams' subnets

---

*Related: [ADR-006](adr-006-multi-region.md)*
