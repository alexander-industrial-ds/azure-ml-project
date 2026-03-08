#!/usr/bin/env bash
# =============================================================================
#  STATUS — Check the current state of all project resources
#  Run this anytime to see what's running and what it's costing.
#
#  USAGE:
#    ./scripts/status.sh
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; GREY='\033[0;37m'; BOLD='\033[1m'; NC='\033[0m'

ok()      { echo -e "  ${GREEN}✓${NC}  $*"; }
missing() { echo -e "  ${RED}✗${NC}  $*"; }
warn()    { echo -e "  ${YELLOW}!${NC}  $*"; }
section() { echo -e "\n${BOLD}${BLUE}$*${NC}"; echo "  $(printf '─%.0s' {1..50})"; }

[[ -f "$CONFIG_FILE" ]] || { echo "config.env not found"; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG_FILE"

echo -e "\n${BOLD}Azure ML Project Status${NC}  —  $(date '+%Y-%m-%d %H:%M:%S')"
echo "Workspace: $WORKSPACE_NAME  |  Resource Group: $RESOURCE_GROUP"

# ── Resource Group ────────────────────────────────────────────────────────────
section "Resource Group"
if az group show --name "$RESOURCE_GROUP" &>/dev/null 2>&1; then
  STATE=$(az group show --name "$RESOURCE_GROUP" --query "properties.provisioningState" -o tsv)
  ok "$RESOURCE_GROUP [$STATE]"
else
  missing "$RESOURCE_GROUP — NOT FOUND"
fi

# ── Workspace ─────────────────────────────────────────────────────────────────
section "Workspace"
if az ml workspace show --name "$WORKSPACE_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null 2>&1; then
  ok "$WORKSPACE_NAME"
  STUDIO_URL="https://ml.azure.com/?wsid=/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/workspaces/$WORKSPACE_NAME"
  echo "     Studio: $STUDIO_URL"
else
  missing "$WORKSPACE_NAME — NOT FOUND"
fi

# ── Compute ───────────────────────────────────────────────────────────────────
section "Compute"
for COMPUTE_NAME in "$CLUSTER_NAME" "$CI_NAME"; do
  if az ml compute show \
      --name "$COMPUTE_NAME" \
      --workspace-name "$WORKSPACE_NAME" \
      --resource-group "$RESOURCE_GROUP" &>/dev/null 2>&1; then
    STATE=$(az ml compute show \
      --name "$COMPUTE_NAME" \
      --workspace-name "$WORKSPACE_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --query "state" -o tsv 2>/dev/null || echo "Unknown")
    if [[ "$STATE" == "Running" || "$STATE" == "Succeeded" ]]; then
      warn "$COMPUTE_NAME [$STATE] ← BILLING ACTIVE"
    else
      ok "$COMPUTE_NAME [$STATE]"
    fi
  else
    missing "$COMPUTE_NAME — NOT FOUND"
  fi
done

# ── Datastores ────────────────────────────────────────────────────────────────
section "Datastores"
az ml datastore list \
  --workspace-name "$WORKSPACE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "[].name" -o tsv 2>/dev/null | while read -r ds; do
  ok "$ds"
done

# ── Data Assets ───────────────────────────────────────────────────────────────
section "Data Assets"
az ml data list \
  --workspace-name "$WORKSPACE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "[].{name:name, version:latestVersion}" -o tsv 2>/dev/null | while read -r name ver; do
  ok "$name  (latest: v$ver)"
done

# ── Environments ──────────────────────────────────────────────────────────────
section "Environments (custom only)"
az ml environment list \
  --workspace-name "$WORKSPACE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?!starts_with(name,'AzureML')].{name:name, version:latestVersion}" -o tsv 2>/dev/null | \
while read -r name ver; do
  ok "$name  (latest: v$ver)"
done

echo ""
echo -e "${BOLD}Cost tip:${NC} Stop compute when not in use:"
echo "  ./scripts/teardown.sh --stop-compute-only"
echo ""
