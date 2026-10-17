#!/usr/bin/env bash
# One-time setup, per environment, of everything the Terraform pipeline depends on but cannot
# create itself: resource providers, remote state storage, the environment's CI identity, its
# federated credentials and Azure RBAC, and the GitHub Environment that wires them together.
#
# Each environment (dev, prod) is its own subscription with its own identity and state, so
# the script runs once per environment against bootstrap/<env>.env.
#
# Every step is idempotent: it checks first and only creates what is missing.
# Requires: az (logged in as Owner of the target subscription), gh (authenticated), bash 3.2+.
#
# Usage: bootstrap/bootstrap.sh <dev|prod> [check|providers|state|identity|federation|rbac|github|all]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USAGE="Usage: $0 <dev|prod> [check|providers|state|identity|federation|rbac|github|all]"

ENVIRONMENT="${1:-}"
STEP="${2:-all}"
case "$ENVIRONMENT" in
  dev | prod) ;;
  *)
    echo "$USAGE" >&2
    exit 2
    ;;
esac

ENV_FILE="$SCRIPT_DIR/$ENVIRONMENT.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Copy $ENVIRONMENT.env.example to $ENVIRONMENT.env and edit it." >&2
  exit 1
fi
# shellcheck source-path=SCRIPTDIR source=dev.env.example
source "$ENV_FILE"

: "${SUBSCRIPTION:?}" "${LOCATION:?}" "${GITHUB_OWNER:?}" "${GITHUB_REPO:?}"
: "${APP_NAME:?}" "${TFSTATE_RG:?}" "${TFSTATE_SA:?}"
TFSTATE_CONTAINER="${TFSTATE_CONTAINER:-tfstate}"
PR_PLAN="${PR_PLAN:-false}"
REQUIRED_REVIEWER="${REQUIRED_REVIEWER:-}"

REPO="$GITHUB_OWNER/$GITHUB_REPO"
OIDC_ISSUER="https://token.actions.githubusercontent.com"
OIDC_AUDIENCE="api://AzureADTokenExchange"
PROVIDERS="Microsoft.Storage Microsoft.Network Microsoft.Compute Microsoft.ManagedIdentity Microsoft.Databricks"

log() { printf '\n==> [%s] %s\n' "$ENVIRONMENT" "$*"; }
ok() { printf '    ok: %s\n' "$*"; }

# Every az call below runs against this environment's subscription only
az account set --subscription "$SUBSCRIPTION"

subscription_id() { az account show --query id -o tsv; }
tenant_id() { az account show --query tenantId -o tsv; }
app_id() { az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv; }
sp_object_id() { az ad sp show --id "$(app_id)" --query id -o tsv; }
state_sa_id() { az storage account show -n "$TFSTATE_SA" -g "$TFSTATE_RG" --query id -o tsv; }

ROLE_CREATED=false
ensure_role() { # role, principal object id, principal type, scope
  if [[ "$(az role assignment list --assignee "$2" --role "$1" --scope "$4" --query "length(@)" -o tsv)" == "0" ]]; then
    az role assignment create --role "$1" --assignee-object-id "$2" \
      --assignee-principal-type "$3" --scope "$4" -o none
    ok "assigned '$1'"
    ROLE_CREATED=true
    return
  fi
  ok "'$1' already assigned"
}

cmd_check() {
  log "Context"
  az account show --query "{subscription:name, user:user.name}" -o table
  gh auth status --hostname github.com >/dev/null && ok "gh authenticated"
  printf '    repo: %s  identity: %s  state: %s/%s\n' "$REPO" "$APP_NAME" "$TFSTATE_RG" "$TFSTATE_SA"
}

cmd_providers() {
  log "Register resource providers"
  local p
  for p in $PROVIDERS; do
    if [[ "$(az provider show -n "$p" --query registrationState -o tsv)" != "Registered" ]]; then
      az provider register -n "$p" --wait -o none
    fi
    ok "$p"
  done
}

cmd_state() {
  log "Terraform state storage"
  if [[ "$(az group exists -n "$TFSTATE_RG")" != "true" ]]; then
    az group create -n "$TFSTATE_RG" -l "$LOCATION" --tags managed=bootstrap environment="$ENVIRONMENT" -o none
  fi
  ok "resource group $TFSTATE_RG"

  if ! az storage account show -n "$TFSTATE_SA" -g "$TFSTATE_RG" -o none 2>/dev/null; then
    az storage account create -n "$TFSTATE_SA" -g "$TFSTATE_RG" -l "$LOCATION" \
      --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 \
      --allow-blob-public-access false --tags managed=bootstrap environment="$ENVIRONMENT" -o none
  fi
  ok "storage account $TFSTATE_SA"

  # Owner is control plane only; the operator also needs data-plane access to create the
  # container and to run Terraform locally with Entra ID auth.
  ensure_role "Storage Blob Data Contributor" "$(az ad signed-in-user show --query id -o tsv)" User "$(state_sa_id)"
  if [[ "$ROLE_CREATED" == "true" ]]; then
    echo "    waiting 60s for RBAC to propagate"
    sleep 60
  fi

  if [[ "$(az storage container exists -n "$TFSTATE_CONTAINER" --account-name "$TFSTATE_SA" --auth-mode login --query exists -o tsv)" != "true" ]]; then
    az storage container create -n "$TFSTATE_CONTAINER" --account-name "$TFSTATE_SA" --auth-mode login -o none
  fi
  ok "container $TFSTATE_CONTAINER"
}

cmd_identity() {
  log "CI identity $APP_NAME"
  if [[ -z "$(app_id)" ]]; then
    az ad app create --display-name "$APP_NAME" -o none
  fi
  ok "app registration $(app_id)"
  if ! az ad sp show --id "$(app_id)" -o none 2>/dev/null; then
    az ad sp create --id "$(app_id)" -o none
  fi
  ok "service principal"
}

federated_credential() { # name, subject
  local id
  id=$(app_id)
  if [[ -n "$(az ad app federated-credential list --id "$id" --query "[?name=='$1'].name" -o tsv)" ]]; then
    ok "$1 already exists"
    return
  fi
  az ad app federated-credential create --id "$id" -o none --parameters \
    "{\"name\":\"$1\",\"issuer\":\"$OIDC_ISSUER\",\"subject\":\"$2\",\"audiences\":[\"$OIDC_AUDIENCE\"]}"
  ok "$1 -> $2"
}

cmd_federation() {
  log "Federated credentials (GitHub OIDC, ID-based subject)"
  # The subject embeds the owner and repo IDs *and* their current names, so renaming the
  # repository requires new credentials: re-run this step after a rename.
  local subj
  subj="repo:${GITHUB_OWNER}@$(gh api "users/$GITHUB_OWNER" --jq .id)/${GITHUB_REPO}@$(gh api "repos/$REPO" --jq .id)"
  # Jobs that declare `environment: <env>` present this subject
  federated_credential "gh-${GITHUB_REPO}-env-${ENVIRONMENT}" "${subj}:environment:${ENVIRONMENT}"
  # PR plan jobs declare no environment and present this one; only dev trusts it
  if [[ "$PR_PLAN" == "true" ]]; then
    federated_credential "gh-${GITHUB_REPO}-pr" "${subj}:pull_request"
  fi
}

# Lets the holder create and delete role assignments for these roles only, which Terraform needs
# to give the Unity Catalog access connector access to lake storage (Storage Blob Data
# Contributor) and to itself (Reader, checked by Unity Catalog when registering the credential).
BLOB_DATA_CONTRIBUTOR_ID="ba92f5b4-2d11-453d-a403-e96b0029c9fe"
READER_ID="acdd72a7-3385-48ef-bd42-f606fba81ae7"
ASSIGNABLE_ROLE_IDS="$BLOB_DATA_CONTRIBUTOR_ID, $READER_ID"
RBAC_CONDITION="((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$ASSIGNABLE_ROLE_IDS})) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$ASSIGNABLE_ROLE_IDS}))"

cmd_rbac() {
  log "Azure RBAC for $APP_NAME"
  local sp scope
  sp=$(sp_object_id)
  scope="/subscriptions/$(subscription_id)"
  ensure_role "Contributor" "$sp" ServicePrincipal "$scope"
  ensure_role "Storage Blob Data Contributor" "$sp" ServicePrincipal "$(state_sa_id)"

  # Contributor can't assign roles. This grant can, but only the roles above.
  local role="Role Based Access Control Administrator" existing
  existing=$(az role assignment list --assignee "$sp" --role "$role" --scope "$scope" --query "[0].{id:id, condition:condition}" -o tsv)
  if [[ -n "$existing" && "${existing#*$'\t'}" == "$RBAC_CONDITION" ]]; then
    ok "'$role' already assigned"
    return
  fi
  if [[ -n "$existing" ]]; then
    # The allowed roles changed: replace the assignment so its condition matches
    az role assignment delete --ids "${existing%%$'\t'*}"
  fi
  az role assignment create --role "$role" --assignee-object-id "$sp" \
    --assignee-principal-type ServicePrincipal --scope "$scope" \
    --condition "$RBAC_CONDITION" --condition-version 2.0 \
    --description "Terraform may assign Storage Blob Data Contributor and Reader only" -o none
  ok "assigned '$role' (Storage Blob Data Contributor and Reader only)"
}

cmd_github() {
  log "GitHub Environment '$ENVIRONMENT' (variables are identifiers, not secrets)"
  local body
  if [[ -n "$REQUIRED_REVIEWER" ]]; then
    body="{\"reviewers\":[{\"type\":\"User\",\"id\":$(gh api "users/$REQUIRED_REVIEWER" --jq .id)}],"
  else
    body="{"
  fi
  body="${body}\"deployment_branch_policy\":{\"protected_branches\":false,\"custom_branch_policies\":true}}"
  gh api -X PUT "repos/$REPO/environments/$ENVIRONMENT" --input - <<<"$body" >/dev/null
  # Only main may deploy to this environment, so no branch can mint its token
  if [[ -z "$(gh api "repos/$REPO/environments/$ENVIRONMENT/deployment-branch-policies" --jq '.branch_policies[] | select(.name=="main") | .name')" ]]; then
    gh api -X POST "repos/$REPO/environments/$ENVIRONMENT/deployment-branch-policies" -f name=main -f type=branch >/dev/null
  fi
  ok "environment, main-only deployments${REQUIRED_REVIEWER:+, reviewer $REQUIRED_REVIEWER}"

  gh variable set AZURE_CLIENT_ID -R "$REPO" -e "$ENVIRONMENT" -b "$(app_id)"
  gh variable set AZURE_SUBSCRIPTION_ID -R "$REPO" -e "$ENVIRONMENT" -b "$(subscription_id)"
  gh variable set TFSTATE_RG -R "$REPO" -e "$ENVIRONMENT" -b "$TFSTATE_RG"
  gh variable set TFSTATE_SA -R "$REPO" -e "$ENVIRONMENT" -b "$TFSTATE_SA"

  # Shared tenant. PR plan jobs run outside any environment, so the PR-trusted environment's
  # values are also set at repo level for them (environment values override these).
  gh variable set AZURE_TENANT_ID -R "$REPO" -b "$(tenant_id)"
  if [[ "$PR_PLAN" == "true" ]]; then
    gh variable set AZURE_CLIENT_ID -R "$REPO" -b "$(app_id)"
    gh variable set AZURE_SUBSCRIPTION_ID -R "$REPO" -b "$(subscription_id)"
    gh variable set TFSTATE_RG -R "$REPO" -b "$TFSTATE_RG"
    gh variable set TFSTATE_SA -R "$REPO" -b "$TFSTATE_SA"
  fi
  gh variable list -R "$REPO" -e "$ENVIRONMENT"
}

case "$STEP" in
  check) cmd_check ;;
  providers) cmd_providers ;;
  state) cmd_state ;;
  identity) cmd_identity ;;
  federation) cmd_federation ;;
  rbac) cmd_rbac ;;
  github) cmd_github ;;
  all)
    cmd_check
    cmd_providers
    cmd_state
    cmd_identity
    cmd_federation
    cmd_rbac
    cmd_github
    ;;
  *)
    echo "$USAGE" >&2
    exit 2
    ;;
esac
