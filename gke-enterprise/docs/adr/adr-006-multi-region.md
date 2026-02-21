# ADR-006: Active/Active Multi-Region with Multi-cluster Ingress

**Status:** Accepted
**Date:** 2025-09-10
**Authors:** Platform Engineering Team
**Deciders:** CTO, Platform Lead, Engineering Director

---

## Context

The platform must meet a 99.99% availability SLA for production workloads. A single regional GKE cluster provides 99.95% SLA — insufficient for the business requirement. We needed a multi-region strategy.

---

## Options Considered

### Option 1: Single Regional Cluster with Zone Redundancy

One GKE cluster in `europe-west1`, spread across 3 availability zones.

**Pros:**
- Simple to operate
- Low cost
- No cross-region latency
- No data replication complexity

**Cons:**
- 99.95% SLA from GKE — does not meet business requirement
- Regional GCP incidents (rare but have occurred) would cause full outage
- No geographic redundancy for latency-sensitive global users

### Option 2: Active/Passive (Hot Standby DR)

Primary cluster in `europe-west1`. DR cluster in `us-central1` kept warm but receiving no traffic. Failover is manual.

**Pros:**
- Simpler traffic management than active/active
- Lower cost than active/active (DR nodes can be minimal)
- Clear primary/secondary ownership

**Cons:**
- Manual failover introduces human delay (RTO > 5 min)
- DR cluster is not exercised by real traffic — failure modes may only be discovered during failover
- Capacity in DR may not be sufficient for full traffic load (requires pre-warming)
- Failback after an incident is risky — state may have diverged

### Option 3: Active/Active with Multi-cluster Ingress

Two clusters (primary: `europe-west1`, DR: `us-central1`) both serving live traffic. Multi-cluster Ingress distributes traffic based on backend health and proximity.

**Pros:**
- Both clusters continuously exercised by production traffic
- Automatic failover — Multi-cluster Ingress removes unhealthy backends within seconds
- RTO < 5 min without human intervention
- Global anycast IP — users routed to nearest healthy region
- Satisfies 99.99% availability requirement (two independent 99.95% clusters)
- Config Sync keeps both clusters in sync continuously

**Cons:**
- Higher base cost — minimum nodes in both regions always running
- Stateful workloads require cross-region data replication (Spanner, Cloud SQL HA)
- More complex to operate — two clusters to upgrade, monitor, and maintain
- Active/active for stateful data requires careful application design (eventual consistency windows)

---

## Decision

**Use active/active multi-region with Multi-cluster Ingress (Option 3).**

The business requirement of 99.99% availability cannot be met with a single region. Active/active is preferred over active/passive because it exercises both clusters continuously (eliminating the "cold DR" problem) and provides automatic failover without human intervention.

The additional cost (~40% more than single-region for baseline nodes) is justified by the availability SLA requirement.

---

## Consequences

**Positive:**
- Meets 99.99% availability SLA
- Automatic failover — no on-call engineer needs to act within seconds of a regional outage
- Global anycast routing reduces latency for users in both Europe and North America
- Both clusters are always tested by real production traffic
- Config Sync eliminates configuration drift between clusters

**Negative:**
- ~40% higher baseline infrastructure cost
- Platform team must manage upgrades for two clusters
- Stateful application teams must use globally replicated data stores (Cloud Spanner or Cloud SQL with cross-region replica) — not all databases support this
- Application teams must design for eventual consistency in edge cases (acceptable for our workloads)

**Stateful data strategy:**

| Data Store | Multi-region approach |
|---|---|
| Cloud Spanner | Native multi-region (global) — no change required |
| Cloud SQL | Create cross-region read replica; promote in DR failover |
| Redis / Memorystore | Region-local caches; application must tolerate cache miss on failover |
| GCS | Multi-region bucket (`europe` or `us`) |

**Cost mitigation:**
- DR cluster uses spot instances for non-critical node pools (batch, dev workloads)
- DR cluster node pools have lower minimum counts (scale up during failover)
- CUDs applied to baseline nodes in primary region only

---

*Related: [ADR-001](adr-001-shared-vpc.md), [ADR-002](adr-002-gke-standard-vs-autopilot.md)*
