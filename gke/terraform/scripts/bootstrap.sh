#!/usr/bin/env bash
# ============================================================
# bootstrap.sh
# Sets up GCS buckets for Terraform state and enables
# necessary GCP APIs before running Terraform.
# Run this ONCE before any terraform commands.
# ============================================================

set -euo pipefail

# ─────────────────────────────────────────────
# Configuration – edit these values
# ─────────────────────────────────────────────
ORG_NAME="${ORG_NAME:-myorg}"
ORG_ID="${ORG_ID:-123456789012}"
BILLING_ACCOUNT="${BILLING_ACCOUNT:-ABCDEF-123456-GHIJKL}"
PRIMARY_REGION="${PRIMARY_REGION:-europe-west1}"

PROJECTS=(
  "host:${ORG_NAME}-shared-vpc-prod"
  "cluster:${ORG_NAME}-gke-prod"
  "services:${ORG_NAME}-shared-services"
  "tfstate:${ORG_NAME}-terraform-state"
)

ENVS=("prod" "staging" "dev")

# ─────────────────────────────────────────────
# Colors
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ─────────────────────────────────────────────
# Verify prerequisites
# ─────────────────────────────────────────────
log "Checking prerequisites..."
command -v gcloud >/dev/null 2>&1 || die "gcloud CLI not found. Install from https://cloud.google.com/sdk"
command -v terraform >/dev/null 2>&1 || die "terraform not found. Install from https://terraform.io"

GCLOUD_ACCOUNT=$(gcloud config get-value account 2>/dev/null)
[[ -z "$GCLOUD_ACCOUNT" ]] && die "Not authenticated. Run: gcloud auth login"
ok "Authenticated as: $GCLOUD_ACCOUNT"

# ─────────────────────────────────────────────
# Create GCP Projects
# ─────────────────────────────────────────────
log "Creating GCP projects..."

TFSTATE_PROJECT="${ORG_NAME}-terraform-state"

for entry in "${PROJECTS[@]}"; do
  project_id="${entry#*:}"

  if gcloud projects describe "$project_id" &>/dev/null; then
    warn "Project $project_id already exists, skipping."
  else
    log "Creating project: $project_id"
    gcloud projects create "$project_id" \
      --organization="$ORG_ID" \
      --name="$project_id"

    gcloud billing projects link "$project_id" \
      --billing-account="$BILLING_ACCOUNT"

    ok "Created: $project_id"
  fi
done

# ─────────────────────────────────────────────
# Create Terraform State Buckets (one per env)
# ─────────────────────────────────────────────
log "Creating Terraform state buckets..."

gcloud services enable storage.googleapis.com \
  --project="$TFSTATE_PROJECT" &>/dev/null

for env in "${ENVS[@]}"; do
  BUCKET="${ORG_NAME}-terraform-state-${env}"

  if gsutil ls -b "gs://$BUCKET" &>/dev/null; then
    warn "Bucket gs://$BUCKET already exists, skipping."
  else
    log "Creating bucket: gs://$BUCKET"
    gsutil mb \
      -p "$TFSTATE_PROJECT" \
      -l "$PRIMARY_REGION" \
      -b on \
      "gs://$BUCKET"

    # Enable versioning for state history
    gsutil versioning set on "gs://$BUCKET"

    # Enable uniform bucket-level access
    gsutil uniformbucketlevelaccess set on "gs://$BUCKET"

    ok "Created: gs://$BUCKET"
  fi
done

# ─────────────────────────────────────────────
# Enable required APIs on all projects
# ─────────────────────────────────────────────
CORE_APIS=(
  "cloudresourcemanager.googleapis.com"
  "compute.googleapis.com"
  "container.googleapis.com"
  "iam.googleapis.com"
  "cloudkms.googleapis.com"
  "secretmanager.googleapis.com"
  "logging.googleapis.com"
  "monitoring.googleapis.com"
  "artifactregistry.googleapis.com"
  "binaryauthorization.googleapis.com"
  "containeranalysis.googleapis.com"
  "servicenetworking.googleapis.com"
  "dns.googleapis.com"
  "pubsub.googleapis.com"
  "orgpolicy.googleapis.com"
)

for entry in "${PROJECTS[@]}"; do
  project_id="${entry#*:}"
  log "Enabling APIs on $project_id..."

  gcloud services enable "${CORE_APIS[@]}" \
    --project="$project_id" \
    --quiet

  ok "APIs enabled on $project_id"
done

# ─────────────────────────────────────────────
# Create CI/CD Service Account
# ─────────────────────────────────────────────
SERVICES_PROJECT="${ORG_NAME}-shared-services"
CICD_SA="cicd-sa"
CICD_SA_EMAIL="${CICD_SA}@${SERVICES_PROJECT}.iam.gserviceaccount.com"

log "Creating CI/CD service account..."

if gcloud iam service-accounts describe "$CICD_SA_EMAIL" \
    --project="$SERVICES_PROJECT" &>/dev/null; then
  warn "CI/CD SA already exists: $CICD_SA_EMAIL"
else
  gcloud iam service-accounts create "$CICD_SA" \
    --project="$SERVICES_PROJECT" \
    --display-name="CI/CD Pipeline Service Account"
  ok "Created CI/CD SA: $CICD_SA_EMAIL"
fi

# Grant CI/CD SA necessary roles
CICD_ROLES=(
  "roles/container.developer"
  "roles/artifactregistry.writer"
  "roles/storage.objectAdmin"
  "roles/binaryauthorization.attestorsViewer"
  "roles/cloudkms.cryptoKeyEncrypterDecrypter"
)

for role in "${CICD_ROLES[@]}"; do
  gcloud projects add-iam-policy-binding "${ORG_NAME}-gke-prod" \
    --member="serviceAccount:$CICD_SA_EMAIL" \
    --role="$role" \
    --quiet
done
ok "CI/CD SA roles assigned."

# ─────────────────────────────────────────────
# Copy example tfvars files
# ─────────────────────────────────────────────
log "Copying example tfvars files..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

for env in "${ENVS[@]}"; do
  EXAMPLE="${ROOT_DIR}/environments/${env}/terraform.tfvars.example"
  TARGET="${ROOT_DIR}/environments/${env}/terraform.tfvars"
  if [[ -f "$EXAMPLE" && ! -f "$TARGET" ]]; then
    cp "$EXAMPLE" "$TARGET"
    warn "Created $TARGET — EDIT THIS FILE before running terraform apply!"
  fi
done

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════"
ok "Bootstrap complete!"
echo "════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Edit environments/prod/terraform.tfvars with your values"
echo "  2. cd terraform/environments/prod"
echo "  3. terraform init"
echo "  4. terraform plan"
echo "  5. terraform apply"
echo ""
echo "  CI/CD Service Account: $CICD_SA_EMAIL"
echo ""
