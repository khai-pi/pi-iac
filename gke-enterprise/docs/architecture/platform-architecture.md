# Platform Architecture

> Enterprise GKE platform on Google Cloud — architecture reference for the `infra-platform` repository.

---

## Table of Contents

- [Overview](#overview)
- [GCP Organization Structure](#gcp-organization-structure)
- [Network Architecture](#network-architecture)
- [GKE Clusters](#gke-clusters)
- [Node Pool Strategy](#node-pool-strategy)
- [Security Architecture](#security-architecture)
- [Multi-tenancy Model](#multi-tenancy-model)
- [High Availability & DR](#high-availability--dr)
- [Observability Stack](#observability-stack)
- [GitOps & CI/CD](#gitops--cicd)
- [Cost Management](#cost-management)
- [Technology Stack](#technology-stack)

---

## Overview

The platform provides application teams with a secure, scalable, and observable foundation for deploying containerized workloads on GKE. The platform team owns the control plane; application teams own their namespaces.

| Property | Value |
|---|---|
| Cloud | Google Cloud Platform |
| Kubernetes | GKE Standard, regional, private |
| IaC | Terraform >= 1.6 |
| GitOps | ArgoCD + Config Sync |
| Service Mesh | Anthos Service Mesh (managed Istio) |
| Primary Region | `europe-west1` |
| DR Region | `us-central1` |
| Environments | `dev` · `staging` · `prod` |

---

## GCP Organization Structure

```
Organization (org.example.com)
│
├── folder: platform-team
│   ├── project: shared-vpc-host          ← Shared VPC, networking
│   ├── project: gke-cluster-prod         ← Production GKE cluster
│   ├── project: gke-cluster-staging      ← Staging GKE cluster
│   ├── project: gke-cluster-dev          ← Dev GKE cluster
│   └── project: shared-services          ← Artifact Registry, KMS, logging
│
└── folder: app-teams
    ├── project: team-payments
    ├── project: team-identity
    └── project: team-data
```

**Why separate projects?**

- Blast radius isolation — a compromised project cannot affect others
- Separate billing, quota limits, and cost attribution per team
- Fine-grained IAM at the project level
- Compliance boundary enforcement (e.g. PCI scope limited to `team-payments`)

---

## Network Architecture

All clusters use **Shared VPC**. The host project owns all networking resources; cluster projects attach as service projects.

```
Shared VPC (project: shared-vpc-host)
│
├── subnet: gke-prod-primary  10.0.0.0/20
│   ├── secondary: pods       10.4.0.0/14
│   └── secondary: services   10.0.16.0/20
│
├── subnet: gke-prod-dr       10.1.0.0/20
│   ├── secondary: pods       10.8.0.0/14
│   └── secondary: services   10.1.16.0/20
│
├── Cloud Router + Cloud NAT  ← egress for private nodes
├── Cloud Armor policy        ← WAF at the edge
└── VPC Service Controls      ← data exfiltration prevention
```

### Traffic Flow

```
Internet
  → Cloud Armor WAF
  → Global Load Balancer (Multi-cluster Ingress)
  → GKE Gateway / Ingress
  → Service → Pod
```

| Decision | Choice | Reason |
|---|---|---|
| Node IP visibility | Private nodes | No public IPs on any node |
| API server access | Master Authorized Networks | Restricted to VPN/on-prem CIDRs |
| Egress | Cloud NAT | Controlled, auditable outbound traffic |
| Dataplane | GKE Dataplane V2 (eBPF) | NetworkPolicy enforcement at kernel level |
| DNS | Cloud DNS private zones | Internal service discovery |

---

## GKE Clusters

One **regional** cluster per environment. Regional clusters spread control plane and nodes across 3 availability zones, providing a 99.95% API server SLA.

### Cluster Configuration

| Feature | Setting |
|---|---|
| Mode | Standard (regional, private) |
| Release channel | `REGULAR` (prod) / `RAPID` (dev) |
| Private nodes | Enabled |
| Workload Identity | Enabled |
| etcd encryption | Cloud KMS (CMEK, 90-day key rotation) |
| Shielded nodes | Enabled — Secure Boot + Integrity Monitoring |
| Binary Authorization | `ENFORCED` (prod) / `DRYRUN_AUDIT_LOG_ONLY` (dev) |
| Dataplane | V2 (eBPF / Cilium) |
| Managed Prometheus | Enabled |
| Logging | `SYSTEM` + `WORKLOAD` + `APISERVER` → Cloud Logging |
| Maintenance window | Saturday–Sunday 02:00–06:00 UTC |

---

## Node Pool Strategy

| Pool | Machine Type | Min/Max | Spot | Purpose |
|---|---|---|---|---|
| `system-pool` | n2-standard-4 | 1 / 3 | No | Platform components (ArgoCD, monitoring, mesh) |
| `general-pool` | n2-standard-8 | 1 / 20 | No | Standard application workloads |
| `spot-pool` | n2-standard-8 | 0 / 50 | Yes | Batch jobs, stateless apps, CI runners |
| `memory-pool` | n2-highmem-16 | 0 / 10 | No | ML inference, data-intensive workloads |

All node pools use:
- Container-Optimized OS (COS) with containerd
- Auto-repair and auto-upgrade enabled
- GKE Metadata Server (`workload-metadata=GKE_METADATA`)
- Shielded VM (Secure Boot + Integrity Monitoring)
- Surge upgrade strategy (`max_surge=1, max_unavailable=0`)

---

## Security Architecture

Security is layered across every level of the stack. See [Security & Compliance](security-compliance.md) for the full guide.

```
Layer          Control
─────────────────────────────────────────────────────────────
Organization   Org policies: no public IPs, no SA keys,
               restrict regions, require OS Login
Network        Cloud Armor WAF, Private nodes, VPC SC
Node           Shielded VMs, Container-Optimized OS
Cluster        Binary Authorization, etcd CMEK,
               Workload Identity
Pod            Pod Security Standards (restricted),
               seccomp RuntimeDefault, dropped capabilities
Identity       Workload Identity (no key files anywhere)
Supply chain   Cloud Build signing → Binary Authorization
Secrets        External Secrets Operator + Secret Manager
East-west      Anthos Service Mesh (mTLS STRICT)
```

### Image Supply Chain

```
Source code
  → Cloud Build (build + sign with KMS-backed attestor)
  → Container Analysis (vulnerability scan)
  → Artifact Registry (immutable SHA digest)
  → Binary Authorization (admission webhook)
  → GKE (pod starts only if attestation verified)
```

---

## Multi-tenancy Model

Each application team gets an isolated namespace with hard boundaries:

| Resource | Purpose |
|---|---|
| `ResourceQuota` | Hard limits on CPU, memory, pods, services, storage |
| `LimitRange` | Default requests/limits injected into containers |
| `NetworkPolicy` | Default-deny-all; explicit allow rules only |
| `Role` / `RoleBinding` | Team members bound to namespace-scoped roles |
| `ServiceAccount` | Dedicated KSA linked to team GSA via Workload Identity |

### RBAC Roles

| Role | Scope | Permissions |
|---|---|---|
| `platform-admin` | Cluster-wide | Full cluster access |
| `namespace-admin` | Namespace | All resources in namespace |
| `developer` | Namespace | Read, exec, deploy updates |
| `viewer` | Namespace | Read-only |

### Default Quota per Team

| Resource | Requests | Limits |
|---|---|---|
| CPU | 10 cores | 20 cores |
| Memory | 20 GiB | 40 GiB |
| Pods | — | 50 |
| Services | — | 20 |
| PVCs | — | 10 |
| Storage | — | 500 GiB |

---

## High Availability & DR

```
                    Cloud DNS / Global LB
                           │
              ┌────────────┴────────────┐
              │                         │
    europe-west1 (Primary)       us-central1 (DR)
    Regional GKE Cluster         Regional GKE Cluster
    3 zones · 99.95% SLA         3 zones · 99.95% SLA
              │                         │
              └────────────┬────────────┘
                           │
                  GKE Fleet (Hub)
                  ├─ Multi-cluster Ingress
                  ├─ Multi-cluster Services
                  └─ Config Sync
```

### Recovery Objectives

| Scenario | RTO | RPO |
|---|---|---|
| Node failure | < 2 min | Zero (stateless) |
| Zone failure | < 5 min | Zero (stateless) |
| Region failure (stateless) | < 5 min | Zero |
| Region failure (stateful) | < 15 min | < 1 min (Spanner) |
| Full cluster rebuild | < 45 min (Terraform) | From last backup |

---

## Observability Stack

| Signal | Collector | Backend |
|---|---|---|
| Logs | Fluent Bit DaemonSet | Cloud Logging |
| Metrics | Managed Prometheus | Cloud Monitoring + Grafana |
| Traces | OpenTelemetry Collector | Cloud Trace |
| Alerts | Cloud Alerting | PagerDuty |
| Dashboards | Grafana | Cluster, SLO, cost, security |

### Alert Severity Levels

| Severity | Examples | Response |
|---|---|---|
| P1 | API server down, region failover triggered | Page immediately, 5 min response |
| P2 | Node NotReady, cert expiry < 7d | Page within 30 min |
| P3 | HPA at max, quota > 80% | Ticket, resolve within 4h |
| P4 | Deprecated API, config drift | Weekly digest |

---

## GitOps & CI/CD

```
Developer pushes code
  → GitHub Actions / Cloud Build
      ├─ Lint, test, security scan (Trivy, Semgrep)
      ├─ Build + sign container image
      └─ Push to Artifact Registry
  → Automated PR to k8s-config repo (update image tag)
  → PR merged
  → ArgoCD / Config Sync detects change
  → Argo Rollouts: canary 5% → 25% → 50% → 100%
      └─ Auto-rollback if SLO analysis fails
```

### Repository Layout

```
github.com/org/
├── infra-platform/    ← This repo (Terraform, cluster config)
├── k8s-config/        ← GitOps source (ArgoCD / Config Sync)
│   ├── cluster/       ← Cluster-scoped resources (CRDs, ClusterRoles)
│   ├── namespaces/    ← Namespace config (quotas, RBAC)
│   └── apps/          ← ArgoCD Application manifests
└── app-*/             ← Individual application repos
```

### Progressive Delivery

| Stage | Traffic | Analysis Window |
|---|---|---|
| Canary | 5% | 5 min |
| Canary | 25% | 10 min |
| Canary | 50% | 10 min |
| Full rollout | 100% | Done |

---

## Cost Management

| Strategy | Tool | Expected Saving |
|---|---|---|
| Spot instances | Spot node pool | 60–90% |
| Committed Use Discounts | GCP CUDs | 37–55% |
| Right-size requests | Vertical Pod Autoscaler | 20–40% |
| Scale to zero (dev/staging) | Cluster Autoscaler | 30–50% |
| Optimal machine selection | Node Auto-Provisioning | 10–20% |

All resources carry labels: `team`, `environment`, `cost-center`, `managed-by` for GKE cost allocation and BigQuery billing export chargeback.

---

## Technology Stack

| Layer | Technology |
|---|---|
| Cloud | Google Cloud Platform |
| Kubernetes | GKE Standard, regional, private |
| IaC | Terraform + `terraform-google-modules` |
| GitOps | ArgoCD + Config Sync |
| Service Mesh | Anthos Service Mesh (managed Istio) |
| Ingress | GKE Gateway API + Cloud Armor |
| Cert Management | cert-manager + GCP Certificate Authority Service |
| Secrets | External Secrets Operator + Secret Manager |
| Policy | Gatekeeper (OPA) + Config Controller |
| Image Security | Binary Authorization + Container Analysis |
| Progressive Delivery | Argo Rollouts |
| Metrics | Managed Prometheus + Cloud Monitoring + Grafana |
| Logging | Cloud Logging + Fluent Bit |
| Tracing | OpenTelemetry + Cloud Trace |
| Alerting | Cloud Alerting + PagerDuty |
| CI/CD | Cloud Build + GitHub Actions |
| Registry | Artifact Registry (containers + Helm) |
| VPA | Vertical Pod Autoscaler |

---

*Document Owner: Platform Engineering Team | Review Cycle: Quarterly*
