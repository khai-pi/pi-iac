# ADR-002: Use GKE Standard over GKE Autopilot

**Status:** Accepted
**Date:** 2025-06-18
**Authors:** Platform Engineering Team
**Deciders:** CTO, Platform Lead

---

## Context

Google offers two GKE operating modes: **Standard** (you manage node pools) and **Autopilot** (Google manages nodes entirely). We evaluated both for the enterprise platform.

---

## Options Considered

### Option 1: GKE Autopilot

Google manages nodes, node pools, and node-level security. You only define pods.

**Pros:**
- Zero node management — no patching, no sizing, no pool creation
- Per-pod billing — pay only for actual pod resource requests
- Google enforces security baselines (pod security, no privileged containers)
- Faster time-to-value for teams

**Cons:**
- Cannot run DaemonSets (only Google-managed system DaemonSets)
- No access to node-level configuration (sysctls, custom kernel parameters)
- Cannot use host networking or privileged containers (even for platform tooling)
- Some platform components require DaemonSets (Fluent Bit, Falco, custom CNI)
- Less control over node machine types for specific workloads (ML, high-memory)
- More expensive for always-on workloads vs. committed node pools

### Option 2: GKE Standard

You manage node pools. Full control over node configuration, machine types, and system DaemonSets.

**Pros:**
- DaemonSets supported — enables Fluent Bit, custom monitoring agents, security tools
- Custom machine types per node pool (spot, high-memory, GPU)
- Full control over node-level security (sysctls, Shielded VM config, OS selection)
- Cluster Autoscaler gives fine-grained scaling control
- Better cost efficiency for predictable, high-utilization workloads with CUDs

**Cons:**
- Node pool management is a platform team responsibility
- Must keep node pools upgraded
- Higher operational overhead vs. Autopilot
- Risk of underprovisioing or overprovisioning nodes

---

## Decision

**Use GKE Standard (Option 2).**

The platform requirements make Autopilot's DaemonSet restriction a blocker. Fluent Bit (log collection), the External Secrets Operator webhook, and the Anthos Service Mesh data plane all require DaemonSets or privileged system access. Additionally, the memory-pool for ML workloads requires specific machine type control that Autopilot does not provide.

The operational overhead of managing node pools is acceptable given the platform team size and the automation provided by Terraform and GKE auto-repair/auto-upgrade.

---

## Consequences

**Positive:**
- Full support for all platform tooling (Fluent Bit, ASM, security agents)
- Custom node pool types (spot, high-memory, GPU) for different workloads
- CUDs on baseline node capacity reduce cost vs. per-pod Autopilot billing
- Node-level security controls (Shielded VMs, COS, custom sysctls)

**Negative:**
- Platform team must manage node pool upgrades (partially mitigated by auto-upgrade)
- Node capacity planning required (mitigated by Cluster Autoscaler and Node Auto-Provisioning)
- More Terraform code to maintain

**Revisit criteria:**

Revisit this decision if:
- Autopilot adds DaemonSet support
- The platform team shrinks and node management becomes unsustainable
- Workload profile shifts to highly variable, short-lived jobs where per-pod billing would be cheaper

---

*Related: [ADR-001](adr-001-shared-vpc.md)*
