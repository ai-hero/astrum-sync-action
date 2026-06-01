#!/usr/bin/env bash
# Materialise the desired Astrum config state for one environment into a
# local directory. Pure function: no AWS calls, no network. The output
# directory structure mirrors the S3 layout the deploy side reads:
#
#   <state-dir>/
#     manifest.yml
#     secrets/<NAME>      # one file per entry in environments.<env>.secrets[]
#     variables/<KEY>     # one file per entry in environments.<env>.variables{}
#
# Variable values support ${REF} substitution: REF is looked up first in
# ASTRUM_GH_VARS, then ASTRUM_GH_SECRETS; unresolved refs become empty.
#
# Usage: build-state.sh <env-name> <manifest-path> <state-dir>
# Env:
#   ASTRUM_GH_VARS    JSON object (default '{}')
#   ASTRUM_GH_SECRETS JSON object (default '{}')

set -euo pipefail

ENV_NAME="${1:?env name required}"
MANIFEST_PATH="${2:?manifest path required}"
STATE_DIR="${3:?state dir required}"

if ! yq -e ".environments.${ENV_NAME}" "${MANIFEST_PATH}" > /dev/null 2>&1; then
  echo "::error::Environment '${ENV_NAME}' is not declared under environments: in ${MANIFEST_PATH}" >&2
  exit 1
fi

GH_VARS="${ASTRUM_GH_VARS:-}"
[ -z "${GH_VARS}" ] && GH_VARS='{}'
GH_SECRETS="${ASTRUM_GH_SECRETS:-}"
[ -z "${GH_SECRETS}" ] && GH_SECRETS='{}'

mkdir -p "${STATE_DIR}/secrets" "${STATE_DIR}/variables"
cp "${MANIFEST_PATH}" "${STATE_DIR}/manifest.yml"

# Secrets: one file per declared name; missing value -> empty file.
yq -o=json ".environments.${ENV_NAME}.secrets // []" "${MANIFEST_PATH}" \
  | jq -r '.[]' | while IFS= read -r NAME; do
  [ -z "${NAME}" ] && continue
  VALUE=$(printf '%s' "${GH_SECRETS}" | jq -r --arg n "${NAME}" '.[$n] // ""')
  printf '%s' "${VALUE}" > "${STATE_DIR}/secrets/${NAME}"
  echo "  ✓ secret ${NAME}"
done

# Variables: one file per declared key, with ${REF} substitution.
VAR_ENTRIES_JSON=$(yq -o=json ".environments.${ENV_NAME}.variables // {}" "${MANIFEST_PATH}" \
  | jq -c 'to_entries[]?')
if [ -n "${VAR_ENTRIES_JSON}" ]; then
  while IFS= read -r ENTRY; do
    [ -z "${ENTRY}" ] && continue
    NAME=$(printf '%s' "${ENTRY}" | jq -r '.key')
    VALUE=$(printf '%s' "${ENTRY}" | jq -r '.value')
    while [[ "${VALUE}" =~ \$\{([A-Z_][A-Z0-9_]*)\} ]]; do
      REF="${BASH_REMATCH[1]}"
      REPL=$(printf '%s' "${GH_VARS}" | jq -r --arg n "${REF}" '.[$n] // empty')
      if [ -z "${REPL}" ]; then
        REPL=$(printf '%s' "${GH_SECRETS}" | jq -r --arg n "${REF}" '.[$n] // empty')
      fi
      VALUE="${VALUE//\$\{${REF}\}/${REPL}}"
    done
    printf '%s' "${VALUE}" > "${STATE_DIR}/variables/${NAME}"
    echo "  ✓ variable ${NAME}"
  done <<< "${VAR_ENTRIES_JSON}"
fi
