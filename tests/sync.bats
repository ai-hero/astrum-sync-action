#!/usr/bin/env bats
# Integration smoke for scripts/sync.sh
#
# Stubs the `aws` CLI by prepending a fake binary to PATH that records its
# args to a file. Verifies sync.sh invokes the right `aws s3 sync --delete`
# call against the expected S3 prefix.

setup() {
  TMP="$(mktemp -d)"
  MANIFEST="${TMP}/astrum.yml"
  CALLS="${TMP}/aws-calls"
  BIN="${TMP}/bin"
  SYNC="${BATS_TEST_DIRNAME}/../scripts/sync.sh"

  mkdir -p "${BIN}"
  # aws stub: record every invocation, exit 0
  cat > "${BIN}/aws" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "${CALLS}"
EOF
  chmod +x "${BIN}/aws"
  PATH="${BIN}:${PATH}"
  export PATH

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
  production:
    gh_environment: prod
    domain: x.example.com
$1
EOF
}

@test "sync invokes 'aws s3 sync' exactly once" {
  write_manifest ""
  run "${SYNC}" production "${MANIFEST}" mybucket myowner myrepo
  [ "$status" -eq 0 ]
  [ "$(wc -l < "${CALLS}")" -eq 1 ]
  grep -F "s3 sync" "${CALLS}"
}

@test "sync includes the --delete flag" {
  write_manifest ""
  run "${SYNC}" production "${MANIFEST}" mybucket myowner myrepo
  [ "$status" -eq 0 ]
  grep -F -- "--delete" "${CALLS}"
}

@test "sync targets the expected s3 prefix" {
  write_manifest ""
  run "${SYNC}" production "${MANIFEST}" mybucket myowner myrepo
  [ "$status" -eq 0 ]
  grep -F "s3://mybucket/myowner/myrepo/production/" "${CALLS}"
}

@test "sync errors when env is missing from manifest (no aws call)" {
  write_manifest ""
  run "${SYNC}" staging "${MANIFEST}" mybucket myowner myrepo
  [ "$status" -ne 0 ]
  [ ! -s "${CALLS}" ]
}

@test "state dir contains manifest + declared secrets + declared variables before sync" {
  # Capture the args passed to aws so we can find the SRC dir (first arg
  # after 's3 sync'). Run aws stub that ALSO copies the SRC dir aside so
  # we can inspect it post-mortem.
  cat > "${BIN}/aws" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "${CALLS}"
# Args are: s3 sync <SRC> <DEST> --delete --no-progress
SRC="\$3"
cp -r "\$SRC" "${TMP}/captured"
EOF
  chmod +x "${BIN}/aws"

  write_manifest "    secrets: [API_KEY]
    variables:
      LOG_LEVEL: info"
  export ASTRUM_GH_SECRETS='{"API_KEY":"sk_test"}'

  run "${SYNC}" production "${MANIFEST}" mybucket myowner myrepo
  [ "$status" -eq 0 ]
  [ -f "${TMP}/captured/manifest.yml" ]
  [ "$(cat "${TMP}/captured/secrets/API_KEY")" = "sk_test" ]
  [ "$(cat "${TMP}/captured/variables/LOG_LEVEL")" = "info" ]
}
