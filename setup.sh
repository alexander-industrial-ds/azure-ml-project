#!/usr/bin/env bash
# =============================================================================
#  AZURE ML PROJECT — MASTER SETUP
#  Pulls the project from GitHub and provisions all Azure ML resources
#
#  USAGE:
#    chmod +x setup.sh
#    ./setup.sh                        # interactive (prompts for values)
#    ./setup.sh --config config.env    # non-interactive (reads from file)
#    ./setup.sh --dry-run              # preview what would be created
#
#  WHAT IT DOES (in order):
#    1. Validates prerequisites (az, python, git)
#    2. Loads config (from file or interactive prompts)
#    3. Logs in to Azure CLI
#    4. Provisions Resource Group
#    5. Provisions Storage Account
#    6. Provisions Azure ML Workspace
#    7. Provisions Compute Instance + Cluster
#    8. Registers Datastores
#    9. Registers Data Assets
#   10. Registers Environments
#   11. Clones / updates the GitHub project
#   12. Uploads data to blob storage
#   13. Prints summary and next steps
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/setup.log"
CONFIG_FILE="$SCRIPT_DIR/config.env"
DRY_RUN=false
START_TIME=$(date +%s)

# ── Color helpers ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}[✓]${NC} $*" | tee -a "$LOG_FILE"; }
info()    { echo -e "${BLUE}[→]${NC} $*" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[✗]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}━━━  $*  ━━━${NC}\n" | tee -a "$LOG_FILE"; }
dry_run() { echo -e "${YELLOW}[DRY-RUN]${NC} Would run: $*"; }

# ── Parse arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)   CONFIG_FILE="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=true; shift ;;
    --help|-h)
      echo "Usage: $0 [--config file.env] [--dry-run]"
      echo ""
      echo "Options:"
      echo "  --config FILE   Load configuration from FILE instead of prompting"
      echo "  --dry-run       Show what would be created without creating anything"
      echo "  --help          Show this help message"
      exit 0 ;;
    *) error "Unknown argument: $1. Use --help for usage." ;;
  esac
done

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║     ☁️  AZURE ML PROJECT SETUP                       ║"
echo "  ║     Full environment provisioning + GitHub clone     ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"
$DRY_RUN && warn "DRY-RUN mode active — no resources will be created"
echo ""

# =============================================================================
# STEP 1 — PREREQUISITES
# =============================================================================
header "STEP 1 · Validating Prerequisites"

check_tool() {
  local tool=$1 install_hint=$2
  if command -v "$tool" &>/dev/null; then
    log "$tool found ($(command -v "$tool"))"
  else
    error "$tool not found. $install_hint"
  fi
}

check_tool "az"     "Install: https://docs.microsoft.com/cli/azure/install-azure-cli"
check_tool "python3" "Install: https://www.python.org/downloads/"
check_tool "pip3"    "Install: comes with Python 3.4+"
check_tool "git"     "Install: https://git-scm.com/downloads"

# Check Azure ML CLI extension
if az extension show --name ml &>/dev/null 2>&1; then
  log "Azure ML CLI extension found"
else
  warn "Azure ML CLI extension not found — installing..."
  $DRY_RUN || az extension add --name ml --yes
fi

# Check Python SDK v2
if python3 -c "import azure.ai.ml" 2>/dev/null; then
  log "azure-ai-ml SDK found"
else
  warn "azure-ai-ml not installed — installing..."
  $DRY_RUN || pip3 install azure-ai-ml azure-identity mlflow azureml-mlflow mltable --quiet
fi

# =============================================================================
# STEP 2 — LOAD CONFIGURATION
# =============================================================================
header "STEP 2 · Loading Configuration"

if [[ -f "$CONFIG_FILE" ]]; then
  log "Loading config from $CONFIG_FILE"
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
else
  warn "No config.env found — entering interactive mode"
  echo ""

  read -rp "  Azure Subscription ID   : " SUBSCRIPTION_ID
  read -rp "  Resource Group name     [rg-azureml-project]: " RESOURCE_GROUP
  RESOURCE_GROUP="${RESOURCE_GROUP:-rg-azureml-project}"

  read -rp "  Azure Region            [eastus2]: " LOCATION
  LOCATION="${LOCATION:-eastus2}"

  read -rp "  Storage Account name    [mlstorage$RANDOM]: " STORAGE_ACCOUNT
  STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-mlstorage$RANDOM}"

  read -rp "  Workspace name          [mlw-project]: " WORKSPACE_NAME
  WORKSPACE_NAME="${WORKSPACE_NAME:-mlw-project}"

  read -rp "  Compute Instance name   [ci-dev]: " CI_NAME
  CI_NAME="${CI_NAME:-ci-dev}"

  read -rp "  Compute Cluster name    [aml-cluster]: " CLUSTER_NAME
  CLUSTER_NAME="${CLUSTER_NAME:-aml-cluster}"

  read -rp "  Cluster VM size         [STANDARD_DS11_V2]: " CLUSTER_SIZE
  CLUSTER_SIZE="${CLUSTER_SIZE:-STANDARD_DS11_V2}"

  read -rp "  GitHub repo URL         : " GITHUB_REPO_URL
  read -rp "  Local project folder    [./project]: " PROJECT_DIR
  PROJECT_DIR="${PROJECT_DIR:-./project}"

  # Save for next time
  echo ""
  read -rp "  Save config for next run? [Y/n]: " SAVE_CONFIG
  if [[ "${SAVE_CONFIG:-Y}" =~ ^[Yy] ]]; then
    cat > "$CONFIG_FILE" << EOF
# Azure ML Project Configuration
# Generated $(date)
SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
RESOURCE_GROUP="$RESOURCE_GROUP"
LOCATION="$LOCATION"
STORAGE_ACCOUNT="$STORAGE_ACCOUNT"
WORKSPACE_NAME="$WORKSPACE_NAME"
CI_NAME="$CI_NAME"
CLUSTER_NAME="$CLUSTER_NAME"
CLUSTER_SIZE="$CLUSTER_SIZE"
GITHUB_REPO_URL="$GITHUB_REPO_URL"
PROJECT_DIR="$PROJECT_DIR"
DATASTORE_NAME="project_datastore"
DATA_CONTAINER="mldata"
ENVIRONMENT_NAME="project-training-env"
EOF
    log "Config saved to $CONFIG_FILE"
  fi
fi

# Defaults for optional vars
DATASTORE_NAME="${DATASTORE_NAME:-project_datastore}"
DATA_CONTAINER="${DATA_CONTAINER:-mldata}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-project-training-env}"

echo ""
info "Configuration summary:"
echo "  Subscription  : $SUBSCRIPTION_ID"
echo "  Resource Group: $RESOURCE_GROUP ($LOCATION)"
echo "  Workspace     : $WORKSPACE_NAME"
echo "  Cluster       : $CLUSTER_NAME ($CLUSTER_SIZE)"
echo "  GitHub Repo   : $GITHUB_REPO_URL"
echo ""

# =============================================================================
# STEP 3 — AZURE LOGIN
# =============================================================================
header "STEP 3 · Azure Authentication"

CURRENT_ACCOUNT=$(az account show --query id -o tsv 2>/dev/null || echo "")
if [[ -n "$CURRENT_ACCOUNT" ]]; then
  log "Already logged in (account: $CURRENT_ACCOUNT)"
  if [[ "$CURRENT_ACCOUNT" != "$SUBSCRIPTION_ID" ]]; then
    info "Switching to subscription $SUBSCRIPTION_ID"
    $DRY_RUN || az account set --subscription "$SUBSCRIPTION_ID"
  fi
else
  info "No active session — launching az login..."
  $DRY_RUN || az login
  $DRY_RUN || az account set --subscription "$SUBSCRIPTION_ID"
fi

log "Active subscription: $SUBSCRIPTION_ID"

# =============================================================================
# STEP 4 — RESOURCE GROUP
# =============================================================================
header "STEP 4 · Resource Group"

if az group show --name "$RESOURCE_GROUP" &>/dev/null 2>&1; then
  log "Resource group already exists: $RESOURCE_GROUP"
else
  info "Creating resource group: $RESOURCE_GROUP in $LOCATION"
  if $DRY_RUN; then
    dry_run "az group create --name $RESOURCE_GROUP --location $LOCATION"
  else
    az group create \
      --name "$RESOURCE_GROUP" \
      --location "$LOCATION" \
      --output none
    log "Resource group created: $RESOURCE_GROUP"
  fi
fi

# =============================================================================
# STEP 5 — STORAGE ACCOUNT
# =============================================================================
header "STEP 5 · Storage Account"

if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null 2>&1; then
  log "Storage account already exists: $STORAGE_ACCOUNT"
else
  info "Creating storage account: $STORAGE_ACCOUNT"
  if $DRY_RUN; then
    dry_run "az storage account create --name $STORAGE_ACCOUNT ..."
  else
    az storage account create \
      --name "$STORAGE_ACCOUNT" \
      --resource-group "$RESOURCE_GROUP" \
      --location "$LOCATION" \
      --sku Standard_LRS \
      --kind StorageV2 \
      --output none
    log "Storage account created: $STORAGE_ACCOUNT"
  fi
fi

# Create data container
if $DRY_RUN; then
  dry_run "az storage container create --name $DATA_CONTAINER ..."
else
  STORAGE_KEY=$(az storage account keys list \
    --account-name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[0].value" -o tsv)

  az storage container create \
    --name "$DATA_CONTAINER" \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$STORAGE_KEY" \
    --output none 2>/dev/null || true
  log "Storage container ready: $DATA_CONTAINER"
fi

# =============================================================================
# STEP 6 — AZURE ML WORKSPACE
# =============================================================================
header "STEP 6 · Azure ML Workspace"

if az ml workspace show \
    --name "$WORKSPACE_NAME" \
    --resource-group "$RESOURCE_GROUP" &>/dev/null 2>&1; then
  log "Workspace already exists: $WORKSPACE_NAME"
else
  info "Creating ML workspace: $WORKSPACE_NAME (this takes ~2 min)..."
  if $DRY_RUN; then
    dry_run "az ml workspace create --name $WORKSPACE_NAME ..."
  else
    az ml workspace create \
      --name "$WORKSPACE_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --location "$LOCATION" \
      --storage-account "$STORAGE_ACCOUNT" \
      --output none
    log "Workspace created: $WORKSPACE_NAME"
  fi
fi

# =============================================================================
# STEP 7 — COMPUTE
# =============================================================================
header "STEP 7 · Compute Resources"

# ── Compute Cluster ───────────────────────────────────────────────────────────
if az ml compute show \
    --name "$CLUSTER_NAME" \
    --workspace-name "$WORKSPACE_NAME" \
    --resource-group "$RESOURCE_GROUP" &>/dev/null 2>&1; then
  log "Compute cluster already exists: $CLUSTER_NAME"
else
  info "Creating compute cluster: $CLUSTER_NAME"
  if $DRY_RUN; then
    dry_run "az ml compute create --type amlcompute --name $CLUSTER_NAME ..."
  else
    az ml compute create \
      --type amlcompute \
      --name "$CLUSTER_NAME" \
      --workspace-name "$WORKSPACE_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --size "$CLUSTER_SIZE" \
      --min-instances 0 \
      --max-instances 4 \
      --idle-time-before-scale-down 120 \
      --output none
    log "Compute cluster created: $CLUSTER_NAME (min=0, max=4)"
  fi
fi

# ── Compute Instance ──────────────────────────────────────────────────────────
if az ml compute show \
    --name "$CI_NAME" \
    --workspace-name "$WORKSPACE_NAME" \
    --resource-group "$RESOURCE_GROUP" &>/dev/null 2>&1; then
  log "Compute instance already exists: $CI_NAME"
else
  info "Creating compute instance: $CI_NAME"
  if $DRY_RUN; then
    dry_run "az ml compute create --type computeinstance --name $CI_NAME ..."
  else
    az ml compute create \
      --type computeinstance \
      --name "$CI_NAME" \
      --workspace-name "$WORKSPACE_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --size STANDARD_DS11_V2 \
      --output none
    log "Compute instance created: $CI_NAME"
  fi
fi

# =============================================================================
# STEP 8 — DATASTORES
# =============================================================================
header "STEP 8 · Datastores"

if $DRY_RUN; then
  dry_run "Register datastore $DATASTORE_NAME → $DATA_CONTAINER"
else
  STORAGE_KEY=$(az storage account keys list \
    --account-name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[0].value" -o tsv)

  python3 "$SCRIPT_DIR/scripts/register_datastore.py" \
    --subscription   "$SUBSCRIPTION_ID" \
    --resource-group "$RESOURCE_GROUP" \
    --workspace      "$WORKSPACE_NAME" \
    --datastore-name "$DATASTORE_NAME" \
    --account-name   "$STORAGE_ACCOUNT" \
    --account-key    "$STORAGE_KEY" \
    --container      "$DATA_CONTAINER"
  log "Datastore registered: $DATASTORE_NAME"
fi

# =============================================================================
# STEP 9 — DATA ASSETS
# =============================================================================
header "STEP 9 · Data Assets"

if $DRY_RUN; then
  dry_run "Register data assets from $PROJECT_DIR/data/"
else
  python3 "$SCRIPT_DIR/scripts/register_data_assets.py" \
    --subscription   "$SUBSCRIPTION_ID" \
    --resource-group "$RESOURCE_GROUP" \
    --workspace      "$WORKSPACE_NAME" \
    --datastore-name "$DATASTORE_NAME" \
    --data-dir       "$PROJECT_DIR/data"
  log "Data assets registered"
fi

# =============================================================================
# STEP 10 — ENVIRONMENTS
# =============================================================================
header "STEP 10 · Environments"

if $DRY_RUN; then
  dry_run "Register environment $ENVIRONMENT_NAME from $PROJECT_DIR/environments/conda.yml"
else
  python3 "$SCRIPT_DIR/scripts/register_environment.py" \
    --subscription    "$SUBSCRIPTION_ID" \
    --resource-group  "$RESOURCE_GROUP" \
    --workspace       "$WORKSPACE_NAME" \
    --env-name        "$ENVIRONMENT_NAME" \
    --conda-file      "$PROJECT_DIR/environments/conda.yml"
  log "Environment registered: $ENVIRONMENT_NAME"
fi

# =============================================================================
# STEP 11 — GITHUB CLONE / UPDATE
# =============================================================================
header "STEP 11 · GitHub Repository"

if [[ -z "${GITHUB_REPO_URL:-}" ]]; then
  warn "No GITHUB_REPO_URL set — skipping clone"
else
  if [[ -d "$PROJECT_DIR/.git" ]]; then
    info "Repo already cloned — pulling latest..."
    if $DRY_RUN; then
      dry_run "git -C $PROJECT_DIR pull"
    else
      git -C "$PROJECT_DIR" pull --rebase
      log "Repository updated: $PROJECT_DIR"
    fi
  else
    info "Cloning $GITHUB_REPO_URL → $PROJECT_DIR"
    if $DRY_RUN; then
      dry_run "git clone $GITHUB_REPO_URL $PROJECT_DIR"
    else
      git clone "$GITHUB_REPO_URL" "$PROJECT_DIR"
      log "Repository cloned: $PROJECT_DIR"
    fi
  fi
fi

# =============================================================================
# STEP 12 — UPLOAD DATA
# =============================================================================
header "STEP 12 · Upload Data to Blob Storage"

DATA_SOURCE="${PROJECT_DIR}/data"
if [[ ! -d "$DATA_SOURCE" ]]; then
  warn "No data/ folder found at $DATA_SOURCE — skipping upload"
else
  if $DRY_RUN; then
    dry_run "az storage blob upload-batch --source $DATA_SOURCE --destination $DATA_CONTAINER"
  else
    STORAGE_KEY=$(az storage account keys list \
      --account-name "$STORAGE_ACCOUNT" \
      --resource-group "$RESOURCE_GROUP" \
      --query "[0].value" -o tsv)

    az storage blob upload-batch \
      --source "$DATA_SOURCE" \
      --destination "$DATA_CONTAINER" \
      --account-name "$STORAGE_ACCOUNT" \
      --account-key  "$STORAGE_KEY" \
      --overwrite \
      --output none
    log "Data uploaded to $DATA_CONTAINER"
  fi
fi

# =============================================================================
# SUMMARY
# =============================================================================
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo -e "${BOLD}${GREEN}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║     ✅  SETUP COMPLETE                               ║"
printf "  ║     Total time: %-35s║\n" "${ELAPSED}s"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${BOLD}Resources created:${NC}"
echo "  Resource Group  : $RESOURCE_GROUP ($LOCATION)"
echo "  Storage Account : $STORAGE_ACCOUNT"
echo "  ML Workspace    : $WORKSPACE_NAME"
echo "  Compute Cluster : $CLUSTER_NAME (0–4 nodes, $CLUSTER_SIZE)"
echo "  Compute Instance: $CI_NAME"
echo "  Datastore       : $DATASTORE_NAME"
echo "  Environment     : $ENVIRONMENT_NAME"
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "  1. Open Azure ML Studio:"
echo "     https://ml.azure.com/?wsid=/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/workspaces/$WORKSPACE_NAME"
echo ""
echo "  2. Open the blueprint notebook on your Compute Instance:"
echo "     Studio → Notebooks → Files → $PROJECT_DIR/notebooks/blueprint.ipynb"
echo ""
echo "  3. Run teardown when done (saves cost):"
echo "     ./scripts/teardown.sh"
echo ""
echo "  Full log: $LOG_FILE"
