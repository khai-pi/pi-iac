# ============================================================
# Module: shared-vpc
# Creates a Shared VPC host project network with subnets,
# Cloud Router, Cloud NAT, and firewall rules for GKE.
# ============================================================

locals {
  network_name = "${var.prefix}-vpc"
}

# ─────────────────────────────────────────────
# Enable required APIs
# ─────────────────────────────────────────────
resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "servicenetworking.googleapis.com",
    "dns.googleapis.com",
  ])

  project            = var.host_project_id
  service            = each.value
  disable_on_destroy = false
}

# ─────────────────────────────────────────────
# VPC Network
# ─────────────────────────────────────────────
resource "google_compute_network" "vpc" {
  project                 = var.host_project_id
  name                    = local.network_name
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"

  depends_on = [google_project_service.apis]
}

# ─────────────────────────────────────────────
# Subnets (one per environment/region)
# ─────────────────────────────────────────────
resource "google_compute_subnetwork" "subnets" {
  for_each = var.subnets

  project                  = var.host_project_id
  name                     = each.key
  region                   = each.value.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = each.value.ip_cidr_range
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "${each.key}-pods"
    ip_cidr_range = each.value.pods_cidr
  }

  secondary_ip_range {
    range_name    = "${each.key}-services"
    ip_cidr_range = each.value.services_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# ─────────────────────────────────────────────
# Cloud Router (for NAT)
# ─────────────────────────────────────────────
resource "google_compute_router" "routers" {
  for_each = var.regions

  project = var.host_project_id
  name    = "${var.prefix}-router-${each.value}"
  region  = each.value
  network = google_compute_network.vpc.id

  bgp {
    asn = 64514
  }
}

# ─────────────────────────────────────────────
# Cloud NAT (egress for private nodes)
# ─────────────────────────────────────────────
resource "google_compute_router_nat" "nats" {
  for_each = var.regions

  project                            = var.host_project_id
  name                               = "${var.prefix}-nat-${each.value}"
  router                             = google_compute_router.routers[each.key].name
  region                             = each.value
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ─────────────────────────────────────────────
# Shared VPC Host Configuration
# ─────────────────────────────────────────────
resource "google_compute_shared_vpc_host_project" "host" {
  project = var.host_project_id
}

resource "google_compute_shared_vpc_service_project" "service_projects" {
  for_each = toset(var.service_project_ids)

  host_project    = var.host_project_id
  service_project = each.value

  depends_on = [google_compute_shared_vpc_host_project.host]
}

# ─────────────────────────────────────────────
# Firewall Rules
# ─────────────────────────────────────────────

# Allow internal traffic within VPC
resource "google_compute_firewall" "allow_internal" {
  project = var.host_project_id
  name    = "${var.prefix}-allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [for s in var.subnets : s.ip_cidr_range]
  priority      = 1000
}

# Allow GKE master to communicate with nodes
resource "google_compute_firewall" "allow_master_to_nodes" {
  project = var.host_project_id
  name    = "${var.prefix}-allow-master-to-nodes"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["443", "8443", "10250"]
  }
  allow {
    protocol = "udp"
    ports    = ["8472"]
  }

  source_ranges = var.master_ipv4_cidrs
  target_tags   = ["gke-node"]
  priority      = 1000
}

# Deny all other ingress (default deny)
resource "google_compute_firewall" "deny_all_ingress" {
  project  = var.host_project_id
  name     = "${var.prefix}-deny-all-ingress"
  network  = google_compute_network.vpc.name
  priority = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
  direction     = "INGRESS"
}

# ─────────────────────────────────────────────
# Private DNS Zone (internal service discovery)
# ─────────────────────────────────────────────
resource "google_dns_managed_zone" "private_zone" {
  project     = var.host_project_id
  name        = "${var.prefix}-private-zone"
  dns_name    = "${var.internal_domain}."
  description = "Private DNS zone for internal service discovery"

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.vpc.id
    }
  }
}
