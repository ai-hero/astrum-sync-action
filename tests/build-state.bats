#!/usr/bin/env bats
# Unit tests for scripts/build-state.sh
#
# Each test writes a synthetic astrum.yml and runs the script against a
# fresh STATE_DIR, then asserts on the materialised file tree. No AWS
# calls; the script is a pure transform.

setup() {
  TMP="$(mktemp -d)"
  STATE_DIR="${TMP}/state"
  MANIFEST="${TMP}/astrum.yml"
  BUILD="${BATS_TEST_DIRNAME}/../scripts/build-state.sh"
  unset ASTRUM_GH_VARS ASTRUM_GH_SECRETS
}

teardown() {
  rm -rf "${TMP}"
}

write_manifest() {
  cat > "${MANIFEST}" <<EOF
version: 1
app:
  name: test-app
environments:
$1
EOF
}

@test "errors when requested env is not in manifest" {
  write_manifest "  production:
    gh_environment: prod
    domain: x.example.com"
  run "${BUILD}" staging "${MANIFEST}" "${STATE_DIR}"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "not declared" ]]
}

@test "minimal manifest writes only manifest.yml" {
  write_manifest "  production:
    gh_environment: prod
    domain: x.example.com"
  run "${BUILD}" production "${MANIFEST}" "${STATE_DIR}"
  [ "$status" -eq 0 ]
  [ -f "${STATE_DIR}/manifest.yml" ]
  [ -z "$(ls "${STATE_DIR}/secrets")" ]
  [ -z "$(ls "${STATE_DIR}/variables")" ]
}

@test "secret with value materialises with that value" {
  write_manifest "  production:
    gh_environment: prod
    domain: x.example.com
    secrets: [API_KEY]"
  export ASTRUM_GH_SECRETS='{"API_KEY":"sk_test_123"}'
  run "${BUILD}" production "${MANIFEST}" "${STATE_DIR}"
  [ "$status" -eq 0 ]
  [ "$(cat "${STATE_DIR}/secrets/API_KEY")" = "sk_test_123" ]
}

@test "secret with missing value yields an empty file (not absent)" {
  write_manifest "  production:
    gh_environment: prod
    domain: x.example.com
    secrets: [MISSING_KEY]"
  export ASTRUM_GH_SECRETS='{}'
  run "${BUILD}" production "${MANIFEST}" "${STATE_DIR}"
  [ "$status" -eq 0 ]
  [ -f "${STATE_DIR}/secrets/MISSING_KEY" ]
  [ ! -s "${STATE_DIR}/secrets/MISSING_KEY" ]
}

@test "literal variable value is written verbatim" {
  write_manifest "  production:
    gh_environment: prod
    domain: x.example.com
    variables:
      LOG_LEVEL: info"
  run "${BUILD}" production "${MANIFEST}" "${STATE_DIR}"
  [ "$status" -eq 0 ]
  [ "$(cat "${STATE_DIR}/variables/LOG_LEVEL")" = "info" ]
}

@test "\${REF} in a variable resolves from ASTRUM_GH_VARS" {
  write_manifest "  production:
    gh_environment: prod
    domain: x.example.com
    variables:
      API_BASE: https://api-\${REGION}.example.com"
  export ASTRUM_GH_VARS='{"REGION":"us-east-1"}'
  run "${BUILD}" production "${MANIFEST}" "${STATE_DIR}"
  [ "$status" -eq 0 ]
  [ "$(cat "${STATE_DIR}/variables/API_BASE")" = "https://api-us-east-1.example.com" ]
}

@test "\${REF} falls back to ASTRUM_GH_SECRETS when var missing" {
  write_manifest "  production:
    gh_environment: prod
    domain: x.example.com
    variables:
      DSN: postgres://user:\${DB_PASSWORD}@host/db"
  export ASTRUM_GH_VARS='{}'
  export ASTRUM_GH_SECRETS='{"DB_PASSWORD":"hunter2"}'
  run "${BUILD}" production "${MANIFEST}" "${STATE_DIR}"
  [ "$status" -eq 0 ]
  [ "$(cat "${STATE_DIR}/variables/DSN")" = "postgres://user:hunter2@host/db" ]
}

@test "\${REF} unresolved (in neither vars nor secrets) becomes empty in place" {
  write_manifest "  production:
    gh_environment: prod
    domain: x.example.com
    variables:
      WRAPPED: prefix-\${UNDEFINED}-suffix"
  run "${BUILD}" production "${MANIFEST}" "${STATE_DIR}"
  [ "$status" -eq 0 ]
  [ "$(cat "${STATE_DIR}/variables/WRAPPED")" = "prefix--suffix" ]
}

@test "vars take precedence over secrets for the same name" {
  write_manifest "  production:
    gh_environment: prod
    domain: x.example.com
    variables:
      ENDPOINT: https://\${HOST}.svc"
  export ASTRUM_GH_VARS='{"HOST":"from-vars"}'
  export ASTRUM_GH_SECRETS='{"HOST":"from-secrets"}'
  run "${BUILD}" production "${MANIFEST}" "${STATE_DIR}"
  [ "$status" -eq 0 ]
  [ "$(cat "${STATE_DIR}/variables/ENDPOINT")" = "https://from-vars.svc" ]
}

@test "multiple secrets and variables co-exist correctly" {
  write_manifest "  production:
    gh_environment: prod
    domain: x.example.com
    secrets: [A, B, C]
    variables:
      X: literal
      Y: \${B}"
  export ASTRUM_GH_SECRETS='{"A":"aa","B":"bb","C":"cc"}'
  run "${BUILD}" production "${MANIFEST}" "${STATE_DIR}"
  [ "$status" -eq 0 ]
  [ "$(cat "${STATE_DIR}/secrets/A")" = "aa" ]
  [ "$(cat "${STATE_DIR}/secrets/B")" = "bb" ]
  [ "$(cat "${STATE_DIR}/secrets/C")" = "cc" ]
  [ "$(cat "${STATE_DIR}/variables/X")" = "literal" ]
  [ "$(cat "${STATE_DIR}/variables/Y")" = "bb" ]
}

@test "manifest.yml is copied byte-for-byte" {
  write_manifest "  production:
    gh_environment: prod
    domain: x.example.com"
  run "${BUILD}" production "${MANIFEST}" "${STATE_DIR}"
  [ "$status" -eq 0 ]
  diff -q "${MANIFEST}" "${STATE_DIR}/manifest.yml"
}
