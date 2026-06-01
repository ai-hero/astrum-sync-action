#!/usr/bin/env bash
# Build the desired Astrum config state into a temp dir and reconcile it
# against S3 via `aws s3 sync --delete`. Names removed from astrum.yml
# become deletes on S3 (delete markers; bucket has versioning + KMS).
#
# Usage: sync.sh <env-name> <manifest-path> <bucket> <owner> <repo>
# Env:   ASTRUM_GH_VARS, ASTRUM_GH_SECRETS

set -euo pipefail

ENV_NAME="${1:?env name required}"
MANIFEST_PATH="${2:?manifest path required}"
BUCKET="${3:?bucket required}"
OWNER="${4:?owner required}"
REPO="${5:?repo required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="s3://${BUCKET}/${OWNER}/${REPO}/${ENV_NAME}"

STATE_DIR="$(mktemp -d)"
trap 'rm -rf "${STATE_DIR}"' EXIT

"${SCRIPT_DIR}/build-state.sh" "${ENV_NAME}" "${MANIFEST_PATH}" "${STATE_DIR}"

echo "Built state:"
find "${STATE_DIR}" -type f | sort | sed 's|^|  |'

echo "Syncing ${STATE_DIR}/ -> ${PREFIX}/ (--delete reconciles orphans)"
aws s3 sync "${STATE_DIR}/" "${PREFIX}/" \
  --delete \
  --no-progress

echo "Sync complete: ${PREFIX}/"
