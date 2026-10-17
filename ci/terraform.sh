#!/usr/bin/env bash
# Runs one environment's Terraform layers in dependency order, the same way in CI and locally.
#
#   lake        storage account, container per domain, access connector   (never destroyed here)
#   azure       resource group and Databricks workspace                    (destroy pauses the env)
#   databricks  Unity Catalog objects and cluster policies, inside the workspace
#
# The databricks layer reads the other two layers' outputs, so it is skipped when the workspace
# or the lake isn't deployed yet (for example while dev is paused).
#
# Usage: ci/terraform.sh <dev|prod> <plan|apply|destroy>
# Needs TFSTATE_RG and TFSTATE_SA, and Azure credentials: ARM_* with OIDC in CI, `az login` locally.

set -euo pipefail

ENVIRONMENT="${1:-}"
MODE="${2:-}"
case "$MODE" in
  plan | apply | destroy) ;;
  *)
    echo "Usage: $0 <dev|prod> <plan|apply|destroy>" >&2
    exit 2
    ;;
esac
ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/infra/envs/$ENVIRONMENT"
[[ -d "$ENV_DIR" ]] || {
  echo "No environment at $ENV_DIR" >&2
  exit 2
}
: "${TFSTATE_RG:?}" "${TFSTATE_SA:?}"

if [[ "$MODE" == "destroy" ]]; then
  LAYERS="azure"
else
  LAYERS="lake azure databricks"
fi

tf() { # layer, terraform args...
  local layer="$1"
  shift
  terraform -chdir="$ENV_DIR/$layer" "$@"
}

notice() { echo "::notice::$*"; }

init() {
  tf "$1" init -input=false \
    -backend-config="resource_group_name=$TFSTATE_RG" \
    -backend-config="storage_account_name=$TFSTATE_SA"
}

# Prints a layer's output, or nothing if the layer has no state or no such output yet
output() { tf "$1" output -raw "$2" 2>/dev/null || true; }

databricks_inputs() {
  TF_VAR_workspace_url="$(output azure workspace_url)"
  TF_VAR_workspace_resource_id="$(output azure workspace_resource_id)"
  TF_VAR_workspace_id="$(output azure workspace_id)"
  TF_VAR_access_connector_id="$(output lake access_connector_id)"
  TF_VAR_storage_account_name="$(output lake storage_account_name)"
  export TF_VAR_workspace_url TF_VAR_workspace_resource_id TF_VAR_workspace_id TF_VAR_access_connector_id TF_VAR_storage_account_name
  [[ -n "$TF_VAR_workspace_url" && -n "$TF_VAR_access_connector_id" ]]
}

for layer in $LAYERS; do
  [[ -d "$ENV_DIR/$layer" ]] || continue
  echo "::group::$ENVIRONMENT/$layer: $MODE"
  init "$layer"

  if [[ "$layer" == "databricks" ]] && ! databricks_inputs; then
    notice "$ENVIRONMENT/databricks skipped: the workspace or the lake isn't deployed yet"
    echo "::endgroup::"
    continue
  fi

  if [[ "$MODE" == "destroy" ]]; then
    tf "$layer" plan -input=false -destroy -out=tfplan
  else
    tf "$layer" plan -input=false -out=tfplan
  fi
  if [[ "$MODE" != "plan" ]]; then
    tf "$layer" apply -input=false -auto-approve tfplan
  fi
  rm -f "$ENV_DIR/$layer/tfplan"
  echo "::endgroup::"
done
