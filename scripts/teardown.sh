#!/usr/bin/env bash
# =============================================================================
#  TEARDOWN — Delete all Azure ML project resources
#  Use this after finishing your project to avoid ongoing costs.
#
#  USAGE:
#    ./scripts/teardown.sh                         # interactive confirm
#    ./scripts/teardown.sh --force                 # skip confirmation
#    ./scripts/teardown.sh --stop-compute-only     # stop compute, keep workspace
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $*"; }
info()  { echo -e "${BLUE}[→]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

FORCE=false
STOP_COMPUTE_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)              FORCE=true; shift ;;
    --stop-compute-only)  STOP_COMPUTE_ONLY=true; shift ;;
    *) error "Unknown argument: $1" ;;
  esac
done

[[ -f "$CONFIG_FILE" ]] || error "config.env not found at $CONFIG_FILE"
# shellcheck disable=SC1090
source "$CONFIG_FILE"

echo -e "${BOLD}${RED}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║     ⚠️   TEARDOWN                                    ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

if $STOP_COMPUTE_ONLY; then
  warn "STOP COMPUTE ONLY mode — workspace and data will be kept"
  echo ""
  info "Stopping compute instance: $CI_NAME"
  az ml compute stop \
    --name "$CI_NAME" \
    --workspace-name "$WORKSPACE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --no-wait \
    --output none 2>/dev/null || warn "Compute instance not found or already stopped"
  log "Compute instance stop initiated"
  exit 0
fi

echo "  This will permanently delete:"
echo "  • Resource Group: $RESOURCE_GROUP"
echo "  • ALL resources inside it (workspace, storage, compute)"
echo ""

if ! $FORCE; then
  read -rp "  Type the resource group name to confirm deletion: " CONFIRM
  [[ "$CONFIRM" == "$RESOURCE_GROUP" ]] || error "Name did not match. Aborted."
fi

info "Deleting resource group $RESOURCE_GROUP (this takes ~5 min)..."
az group delete \
  --name "$RESOURCE_GROUP" \
  --yes \
  --no-wait

log "Deletion initiated for: $RESOURCE_GROUP"
warn "Resources will continue deleting in the background."
echo "  Check status: az group show --name $RESOURCE_GROUP"
