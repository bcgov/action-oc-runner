#!/usr/bin/env bash
# ponytail: assert-based check for should_use_proxy.sh; no framework.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DECIDE="${ROOT}/scripts/should_use_proxy.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

# expect_rc expect_stdout repo server proxy label
check() {
  local rc=0 out
  out="$(GITHUB_REPOSITORY="$3" OC_SERVER="$4" OC_PROXY="$5" bash "${DECIDE}" 2>/dev/null)" || rc=$?
  [ "${rc}" -eq "$1" ] || fail "$6: expected rc $1, got ${rc}"
  [ "${out}" = "$2" ] || fail "$6: expected '${2}', got '${out}'"
}

check 0 "https://oc-proxy.apps.silver.devops.gov.bc.ca" \
  "bcgov/action-oc-runner" "https://api.gold.devops.gov.bc.ca:6443" "" \
  "bcgov on gold uses the Silver proxy"
check 0 "https://oc-proxy.apps.silver.devops.gov.bc.ca" \
  "bcgov-c/something" "https://api.silver.devops.gov.bc.ca:6443" "" \
  "bcgov-c on silver uses the same proxy"
check 0 "https://localhost:3129" \
  "bcgov/action-oc-runner" "https://api.gold.devops.gov.bc.ca:6443" "https://localhost:3129" \
  "override wins for CI"
check 1 "" \
  "otherorg/app" "https://api.gold.devops.gov.bc.ca:6443" "" \
  "unrelated org skips even with the default"
check 1 "" \
  "otherorg/app" "https://api.gold.devops.gov.bc.ca:6443" "https://oc-proxy.example" \
  "unrelated org skips even with an override"
check 1 "" \
  "bcgov/action-oc-runner" "https://api.example.com:6443" "" \
  "bcgov on someone else's cluster"
check 1 "" \
  "bcgov/action-oc-runner" "https://api.gold.evil.example:6443" "" \
  "lookalike gold host"
check 1 "" \
  "bcgov-extra/app" "https://api.gold.devops.gov.bc.ca:6443" "" \
  "owner prefix must not match"

echo "should_use_proxy_test.sh: ok"
