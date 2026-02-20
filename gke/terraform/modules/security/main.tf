# ============================================================
# Module: security
# Cloud Armor WAF policy, Secret Manager, org-level IAM
# policies, and VPC Service Controls configuration.
# ============================================================

# ─────────────────────────────────────────────
# Enable APIs
# ─────────────────────────────────────────────
resource "google_project_service" "apis" {
  for_each = toset([
    "secretmanager.googleapis.com",
    "cloudarmor.googleapis.com",
    "accesscontextmanager.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ─────────────────────────────────────────────
# Cloud Armor Security Policy (WAF)
# ─────────────────────────────────────────────
resource "google_compute_security_policy" "waf" {
  project     = var.project_id
  name        = "${var.prefix}-waf-policy"
  description = "WAF policy for GKE ingress with OWASP Top 10 protection"

  # ── Adaptive Protection (ML-based DDoS) ────
  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable          = true
      rule_visibility = "STANDARD"
    }
  }

  # ── Default deny ─────────────────────────────
  rule {
    action   = "deny(403)"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default deny all"
  }

  # ── Allow specific IP ranges ─────────────────
  rule {
    action   = "allow"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = var.allowed_ip_ranges
      }
    }
    description = "Allow whitelisted IP ranges"
  }

  # ── OWASP Top 10 – XSS ───────────────────────
  rule {
    action   = "deny(403)"
    priority = "2000"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-v33-stable')"
      }
    }
    description = "Block XSS attacks"
  }

  # ── OWASP Top 10 – SQLi ──────────────────────
  rule {
    action   = "deny(403)"
    priority = "2001"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-v33-stable')"
      }
    }
    description = "Block SQL injection"
  }

  # ── OWASP Top 10 – LFI ───────────────────────
  rule {
    action   = "deny(403)"
    priority = "2002"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('lfi-v33-stable')"
      }
    }
    description = "Block local file inclusion"
  }

  # ── OWASP Top 10 – RFI ───────────────────────
  rule {
    action   = "deny(403)"
    priority = "2003"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('rfi-v33-stable')"
      }
    }
    description = "Block remote file inclusion"
  }

  # ── Rate limiting ─────────────────────────────
  rule {
    action   = "throttle"
    priority = "3000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = 1000
        interval_sec = 60
      }
    }
    description = "Rate limit: 1000 requests per minute per IP"
  }
}

# ─────────────────────────────────────────────
# Secret Manager – Platform Secrets
# ─────────────────────────────────────────────

# Cluster kubeconfig secret
resource "google_secret_manager_secret" "platform_secrets" {
  for_each = var.secret_ids

  project   = var.project_id
  secret_id = each.value

  replication {
    user_managed {
      replicas {
        location = var.primary_region
      }
      dynamic "replicas" {
        for_each = var.dr_region != "" ? [1] : []
        content {
          location = var.dr_region
        }
      }
    }
  }

  labels = {
    managed-by  = "terraform"
    environment = var.environment
  }
}

# ─────────────────────────────────────────────
# Cloud Audit Logging – Force-enable for all
# ─────────────────────────────────────────────
resource "google_project_iam_audit_config" "all_services" {
  project = var.project_id
  service = "allServices"

  audit_log_config {
    log_type = "ADMIN_READ"
  }
  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

# ─────────────────────────────────────────────
# Org Policy Constraints
# ─────────────────────────────────────────────

# Restrict which GCP regions resources can be created in
resource "google_org_policy_policy" "allowed_regions" {
  count  = var.org_id != "" ? 1 : 0
  name   = "organizations/${var.org_id}/policies/gcp.resourceLocations"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      values {
        allowed_values = [
          "in:europe-locations",
          "in:us-locations",
        ]
      }
    }
  }
}

# Disable public IPs on Compute instances
resource "google_org_policy_policy" "no_public_ip" {
  count  = var.org_id != "" ? 1 : 0
  name   = "organizations/${var.org_id}/policies/compute.vmExternalIpAccess"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      deny_all = "TRUE"
    }
  }
}

# Disable service account key creation (enforce Workload Identity)
resource "google_org_policy_policy" "no_sa_keys" {
  count  = var.org_id != "" ? 1 : 0
  name   = "organizations/${var.org_id}/policies/iam.disableServiceAccountKeyCreation"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# Require OS Login on VMs
resource "google_org_policy_policy" "require_os_login" {
  count  = var.org_id != "" ? 1 : 0
  name   = "organizations/${var.org_id}/policies/compute.requireOsLogin"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}
