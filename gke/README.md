# Enterprise Kubernetes Infrastructure on Google Cloud (GKE)

> A production-grade, multi-cluster, multi-tenant Kubernetes platform built on Google Kubernetes Engine with security, observability, GitOps, and cost management built-in from day one.

---

## Table of Contents

- [Overview](#overview)
- [Architecture Diagram](#architecture-diagram)
- [Design Principles](#design-principles)
- [Infrastructure Layers](#infrastructure-layers)
  - [1. Organization & Project Structure](#1-organization--project-structure)
  - [2. Networking](#2-networking)
  - [3. GKE Clusters](#3-gke-clusters)
  - [4. Security](#4-security)
  - [5. Multi-tenancy](#5-multi-tenancy)
  - [6. Multi-cluster & High Availability](#6-multi-cluster--high-availability)
  - [7. Observability](#7-observability)
  - [8. GitOps & CI/CD](#8-gitops--cicd)
  - [9. Cost Management](#9-cost-management)
- [Technology Stack](#technology-stack)
- [Repository Structure](#repository-structure)
- [Getting Started](#getting-started)
- [Runbooks](#runbooks)
- [Contributing](#contributing)

---

## Overview

This repository defines the architecture and Infrastructure-as-Code (IaC) for an enterprise-grade Kubernetes platform on Google Cloud. The platform is designed to support multiple application teams, enforce security and compliance requirements, and provide a consistent developer experience across all environments (`dev`, `staging`, `prod`).

| Property | Value |
|---|---|
| Cloud Provider | Google Cloud Platform (GCP) |
| Kubernetes Distribution | Google Kubernetes Engine (GKE) |
| IaC Tool | Terraform |
| GitOps Engine | ArgoCD / Config Sync |
| Service Mesh | Anthos Service Mesh (Istio) |
| Environments | dev · staging · prod |
| Primary Region | `europe-west1` |
| DR Region | `us-central1` |

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        GCP Organization                                  │
│                                                                           │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  folder: platform-team                                            │   │
│  │                                                                    │   │
│  │  ┌──────────────────┐   ┌──────────────────┐                     │   │
│  │  │  project:         │   │  project:         │                     │   │
│  │  │  shared-vpc-host  │   │  gke-cluster-prod │                     │   │
│  │  │                   │   │                   │                     │   │
│  │  │  VPC Network      │   │  GKE Regional     │                     │   │
│  │  │  ├─ gke-subnet    │◄──│  Cluster          │                     │   │
│  │  │  ├─ pods range    │   │  ├─ zone a         │                     │   │
│  │  │  └─ svc range     │   │  ├─ zone b         │                     │   │
│  │  │                   │   │  └─ zone c         │                     │   │
│  │  │  Cloud NAT        │   │                   │                     │   │
│  │  │  Cloud Router     │   │  Private Nodes    │                     │   │
│  │  └──────────────────┘   │  Private Master   │                     │   │
│  │                          └──────────────────┘                     │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                           │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  folder: app-teams                                                │   │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐                    │   │
│  │  │ project:  │  │ project:  │  │ project:  │                    │   │
│  │  │ team-a    │  │ team-b    │  │ team-c    │   (service projects)│   │
│  │  └───────────┘  └───────────┘  └───────────┘                    │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                           │
│                          ┌─────────────────────┐                         │
│                          │  Shared Services     │                         │
│                          │  ├─ Artifact Registry│                         │
│                          │  ├─ Secret Manager   │                         │
│                          │  ├─ Cloud KMS        │                         │
│                          │  ├─ Cloud Armor      │                         │
│                          │  └─ Cloud Logging    │                         │
│                          └─────────────────────┘                         │
└─────────────────────────────────────────────────────────────────────────┘

Internet → Cloud Armor (WAF) → Global Load Balancer (Multi-cluster Ingress)
               ↓                         ↓
         europe-west1               us-central1
         GKE Cluster (Primary)      GKE Cluster (DR)
               ↕                         ↕
         Config Sync ←── GitHub ──► ArgoCD
```

---

## Design Principles

**1. Security by Default**
Every cluster component is locked down from the start. Private nodes, Workload Identity, Binary Authorization, etcd encryption, and Pod Security Standards are non-negotiable defaults — not optional add-ons.

**2. GitOps as the Single Source of Truth**
No manual `kubectl apply` in production. All cluster state is declared in Git and continuously reconciled by ArgoCD/Config Sync. Drift is detected and corrected automatically.

**3. Multi-tenancy with Hard Boundaries**
Application teams operate in isolated namespaces with dedicated ResourceQuotas, NetworkPolicies, and RBAC. The platform team owns the control plane; app teams own their namespaces.

**4. Observability is Not Optional**
Every workload emits structured logs, metrics, and traces from day one. The platform provides a managed observability stack with no per-team setup required.

**5. Infrastructure is Immutable**
Nodes are never patched in place. Node pool upgrades replace nodes via surge upgrades. Cluster configuration changes go through Terraform plan/apply in CI.

**6. Cost Awareness**
Spot instances for non-critical workloads, VPA for right-sizing, and cost allocation labels on every resource so teams can see what they spend.

---

## Infrastructure Layers

### 1. Organization & Project Structure

The GCP resource hierarchy follows a hub-and-spoke model with separation of concerns across projects.

```
Organization (org.example.com)
│
├── folder: platform-team
│   ├── project: shared-vpc-host          ← Shared VPC host, networking
│   ├── project: gke-cluster-prod         ← Production GKE cluster
│   ├── project: gke-cluster-staging      ← Staging GKE cluster
│   ├── project: gke-cluster-dev          ← Dev GKE cluster
│   └── project: shared-services          ← Artifact Registry, KMS, Logging
│
└── folder: app-teams
    ├── project: team-payments
    ├── project: team-identity
    └── project: team-data
```

**Why separate projects?**
- Blast radius isolation — a compromised project can't affect others
- Separate billing and quota limits per team
- Fine-grained IAM at the project level
- Compliance boundary enforcement (e.g., PCI scope limited to `team-payments`)

---

### 2. Networking

All clusters use **Shared VPC** — network resources live in the host project, clusters run as service projects attached to it.

```
Shared VPC (project: shared-vpc-host)
│
├── subnet: gke-prod-subnet (10.0.0.0/20)
│   ├── secondary range: pods     (10.4.0.0/14)
│   └── secondary range: services (10.0.16.0/20)
│
├── Cloud Router → Cloud NAT      ← Egress for private nodes
├── Cloud Armor policy            ← WAF at the edge
└── VPC Service Controls          ← Data exfiltration prevention
```

**Key decisions:**

| Decision | Choice | Reason |
|---|---|---|
| Node IP visibility | Private nodes only | No public IPs on any node |
| API server access | Master Authorized Networks | Restricted to VPN/on-prem CIDRs |
| Egress | Cloud NAT | Controlled, auditable outbound traffic |
| DNS | Cloud DNS private zones | Internal service discovery |
| Dataplane | GKE Dataplane V2 (eBPF) | NetworkPolicy enforcement, better observability |

---

### 3. GKE Clusters

One **regional** cluster per environment. Regional clusters spread control plane and nodes across 3 availability zones, giving 99.95% SLA on the API server.

**Cluster configuration highlights:**

| Feature | Setting |
|---|---|
| Mode | Standard (for full control) |
| Release channel | `REGULAR` |
| Private cluster | Enabled |
| Workload Identity | Enabled |
| Shielded nodes | Enabled (Secure Boot + Integrity Monitoring) |
| etcd encryption | Cloud KMS (CMEK) |
| Dataplane | V2 (eBPF / Cilium) |
| Logging | SYSTEM + WORKLOAD → Cloud Logging |
| Monitoring | SYSTEM → Cloud Monitoring + Managed Prometheus |
| Binary Authorization | ENFORCED |

**Node Pool Strategy:**

```
┌─────────────────────────────────────────────────────┐
│  Node Pools                                          │
│                                                      │
│  system-pool      n2-standard-4   On-demand  x3     │
│  │  → kube-system, istio, argocd, monitoring        │
│                                                      │
│  general-pool     n2-standard-8   On-demand  x3–30  │
│  │  → general application workloads                 │
│                                                      │
│  spot-pool        n2-standard-8   Spot       x0–50  │
│  │  → batch jobs, stateless apps, CI runners        │
│                                                      │
│  memory-pool      n2-highmem-16   On-demand  x0–10  │
│     → ML inference, data-intensive workloads         │
└─────────────────────────────────────────────────────┘
```

All node pools have:
- Auto-repair and auto-upgrade enabled
- GKE Metadata Server (`workload-metadata=GKE_METADATA`)
- Shielded VM features
- OS: Container-Optimized OS (COS)

---

### 4. Security

Security is layered across every level of the stack.

#### Identity & Access

```
Developer → Google Identity → IAM → Kubernetes RBAC
                                 → Namespace RBAC bindings
                                 → (never direct cluster-admin)
```

- **Workload Identity**: Pods assume GCP service account permissions via projected service account tokens — no keys, no secrets mounted as files.
- **Break-glass access**: Emergency `cluster-admin` requires a separate privileged project, MFA, and generates an audit log alert.

#### Image Supply Chain

```
Source Code
    ↓
Cloud Build (build + sign image)
    ↓
Artifact Registry (vulnerability scan via Container Analysis)
    ↓
Binary Authorization policy check (only signed images from approved registry)
    ↓
GKE (admission webhook blocks unsigned/unscanned images)
```

#### Pod Security

All namespaces enforce the `restricted` Pod Security Standard:
- No privilege escalation
- Non-root containers only
- Read-only root filesystem where possible
- Dropped `ALL` Linux capabilities
- `seccomp: RuntimeDefault`

#### Network Security

- Default-deny `NetworkPolicy` on all namespaces
- Explicit allow rules per service
- Cloud Armor WAF in front of all external ingress (OWASP Top 10 rules, rate limiting, geo-blocking)
- Anthos Service Mesh for mTLS between services inside the cluster

#### Secrets Management

Secrets never live in etcd. The **External Secrets Operator** syncs from **Secret Manager** into Kubernetes secrets at runtime.

```
Secret Manager → External Secrets Operator → Kubernetes Secret → Pod env/volume
```

---

### 5. Multi-tenancy

Each application team gets an isolated namespace (or set of namespaces) with:

```yaml
# Per-team controls applied via Config Sync
ResourceQuota       → CPU, memory, pod count limits
LimitRange          → Default requests/limits for containers
NetworkPolicy       → Default deny + explicit allow rules
RoleBinding         → Team members bound to team-scoped roles only
ServiceAccount      → Dedicated KSA linked to team's GSA (Workload Identity)
```

**RBAC model:**

| Role | Scope | Permissions |
|---|---|---|
| `platform-admin` | Cluster-wide | Full cluster access |
| `namespace-admin` | Namespace | Deploy, configure, debug |
| `developer` | Namespace | Read logs, exec into pods, read resources |
| `viewer` | Namespace | Read-only across namespace |

Teams onboard via a self-service Terraform module that creates the namespace, quota, RBAC, and Workload Identity bindings automatically.

---

### 6. Multi-cluster & High Availability

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
                  └─ Config Sync (both clusters same config)
```

**Failover strategy:**
- Multi-cluster Ingress routes traffic based on backend health
- If primary region is unhealthy, all traffic automatically routes to DR
- RTO target: < 5 minutes | RPO target: < 1 minute (for stateless workloads)
- Stateful workloads use **Cloud Spanner** or **Cloud SQL with cross-region replicas**

---

### 7. Observability

The platform provides a full observability stack with zero per-team configuration required.

```
Workload Pods
│
├─ Logs     → Fluent Bit (DaemonSet) → Cloud Logging → Log-based metrics, alerts
├─ Metrics  → Managed Prometheus → Cloud Monitoring → Grafana dashboards
└─ Traces   → OpenTelemetry Collector → Cloud Trace → Latency analysis
```

**Key dashboards (Grafana):**

| Dashboard | Description |
|---|---|
| Cluster Overview | Node health, pod counts, resource utilization |
| Namespace Quota | Per-team CPU/memory usage vs. quota |
| SLO Dashboard | Error rate, latency p50/p95/p99 per service |
| Security | Policy violations, failed auth, anomaly detection |
| Cost | Per-namespace spend attribution |

**Alerting policy (PagerDuty integration):**

| Severity | Examples | Response |
|---|---|---|
| P1 | API server down, >50% pods CrashLooping | Page on-call immediately |
| P2 | Node Not Ready, PVC pending >10m | Page on-call within 30m |
| P3 | HPA at max replicas, quota >80% | Ticket created automatically |
| P4 | Deprecated API usage, drift detected | Weekly digest email |

---

### 8. GitOps & CI/CD

**Repository layout:**

```
github.com/org/
├── infra-platform/          ← This repo (Terraform, cluster config)
├── k8s-config/              ← GitOps repo (Config Sync / ArgoCD source)
│   ├── cluster/             ← Cluster-scoped resources (CRDs, ClusterRoles)
│   ├── namespaces/          ← Namespace config (quotas, RBAC)
│   └── apps/                ← ArgoCD Application manifests
└── app-*/                   ← Individual application repos
```

**Deployment pipeline:**

```
Developer pushes code
        ↓
GitHub Actions / Cloud Build
  ├─ Lint, test, security scan (Trivy, Semgrep)
  ├─ Build & sign container image
  ├─ Push to Artifact Registry
  └─ Update image tag in k8s-config repo (PR)
        ↓
Platform team review (automated for non-prod)
        ↓
PR merged to k8s-config
        ↓
Config Sync / ArgoCD detects change
        ↓
Progressive delivery via Argo Rollouts
  ├─ Canary: 5% → 25% → 50% → 100%
  ├─ Automated analysis (error rate, latency)
  └─ Auto-rollback if SLOs breached
```

---

### 9. Cost Management

| Strategy | Tool | Expected Saving |
|---|---|---|
| Spot nodes for batch/stateless | Node pool with `--spot` | 60–90% |
| Right-size container requests | Vertical Pod Autoscaler | 20–40% |
| Cluster autoscaling (scale to zero) | Cluster Autoscaler | 30–50% (off-hours) |
| Committed Use Discounts | GCP CUDs for baseline capacity | 37–55% |
| Per-namespace cost attribution | GKE cost allocation + labels | Visibility only |

All GKE resources are labeled with `team`, `environment`, `cost-center` for accurate chargeback reporting via **Cloud Billing export to BigQuery**.

---

## Technology Stack

| Layer | Technology |
|---|---|
| **Cloud** | Google Cloud Platform |
| **Kubernetes** | GKE Standard, regional, private |
| **IaC** | Terraform + `terraform-google-modules` |
| **GitOps** | ArgoCD + Config Sync |
| **Service Mesh** | Anthos Service Mesh (managed Istio) |
| **Ingress** | GKE Gateway API + Cloud Armor |
| **Cert Management** | cert-manager + GCP Certificate Authority Service |
| **Secrets** | External Secrets Operator + Secret Manager |
| **Policy** | Gatekeeper (OPA) + Config Controller |
| **Image Security** | Binary Authorization + Artifact Analysis |
| **Progressive Delivery** | Argo Rollouts |
| **Metrics** | Managed Prometheus + Cloud Monitoring |
| **Logging** | Cloud Logging + Fluent Bit |
| **Tracing** | OpenTelemetry + Cloud Trace |
| **Dashboards** | Grafana + Cloud Monitoring |
| **Alerting** | Cloud Alerting + PagerDuty |
| **CI/CD** | Cloud Build + GitHub Actions |
| **Container Registry** | Artifact Registry |

---

## Repository Structure

```
infra-platform/
│
├── terraform/
│   ├── modules/
│   │   ├── gke-cluster/         ← Reusable GKE cluster module
│   │   ├── shared-vpc/          ← VPC, subnets, Cloud NAT
│   │   ├── gke-node-pool/       ← Node pool module
│   │   └── team-namespace/      ← Team onboarding module
│   │
│   └── environments/
│       ├── dev/
│       ├── staging/
│       └── prod/
│           ├── main.tf
│           ├── variables.tf
│           └── terraform.tfvars
│
├── k8s/
│   ├── platform/                ← Platform-level K8s resources
│   │   ├── argocd/
│   │   ├── cert-manager/
│   │   ├── external-secrets/
│   │   ├── gatekeeper/
│   │   └── monitoring/
│   └── teams/                   ← Team namespace scaffolding
│
├── docs/
│   ├── architecture/
│   ├── runbooks/
│   └── adr/                     ← Architecture Decision Records
│
├── scripts/
│   └── bootstrap.sh             ← Initial cluster bootstrap
│
└── README.md                    ← This file
```

---

## Getting Started

### Prerequisites

```bash
# Required tools
gcloud CLI >= 450.0.0
terraform >= 1.6.0
kubectl >= 1.28
helm >= 3.13
argocd CLI >= 2.9
```

### 1. Bootstrap GCP Organization

```bash
# Authenticate
gcloud auth application-default login

# Set org-level variables
export ORG_ID="123456789"
export BILLING_ACCOUNT="ABCDEF-123456-GHIJKL"
```

### 2. Deploy Foundation (Shared VPC + Projects)

```bash
cd terraform/environments/prod
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

### 3. Bootstrap Cluster

```bash
# Get cluster credentials
gcloud container clusters get-credentials prod-cluster \
  --region=europe-west1 \
  --project=gke-cluster-prod

# Install platform components
./scripts/bootstrap.sh --env=prod
```

### 4. Install ArgoCD & Sync Config

```bash
kubectl apply -k k8s/platform/argocd/
argocd app sync platform-apps
```

### 5. Onboard a Team

```bash
cd terraform/environments/prod
terraform apply -var="teams=[\"team-payments\"]"
```

---

## Runbooks

| Runbook | Description |
|---|---|
| [Node Not Ready](docs/runbooks/node-not-ready.md) | Diagnose and recover unresponsive nodes |
| [Pod CrashLoopBackOff](docs/runbooks/crashloop.md) | Debug crashing pods |
| [Cluster Upgrade](docs/runbooks/cluster-upgrade.md) | Step-by-step GKE control plane + node upgrade |
| [Incident Response](docs/runbooks/incident-response.md) | On-call escalation and communication process |
| [Disaster Recovery](docs/runbooks/dr-failover.md) | Failover to DR region |
| [Certificate Rotation](docs/runbooks/cert-rotation.md) | Rotate TLS certificates |
| [Secret Rotation](docs/runbooks/secret-rotation.md) | Rotate secrets in Secret Manager |

---

## Contributing

1. File an issue or RFC in GitHub for any architectural changes
2. All Terraform changes require `terraform plan` output in the PR
3. All K8s manifest changes are validated via `kubeval` + `conftest` in CI
4. Architecture Decision Records (ADRs) are required for significant decisions — see `docs/adr/`
5. Changes to production require approval from two platform team members

---

## License

Copyright © 2026 Your Organization. Internal use only.