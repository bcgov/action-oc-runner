#!/usr/bin/env bash
# ponytail: assert-based check for should_use_proxy.sh; no framework.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DECIDE="${ROOT}/scripts/should_use_proxy.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

check() { # expect_rc repo server proxy label
  local got rc=0
  got="$(GITHUB_REPOSITORY="$2" OC_SERVER="$3" OC_PROXY="$4" bash "${DECIDE}" 2>&1)" || rc=$?
  [ "${rc}" -eq "$1" ] || fail "$5: expected rc $1, got ${rc} (${got})"
}

check 0 "bcgov/action-oc-runner" "https://api.gold.devops.gov.bc.ca:6443" "https://oc-proxy.example" \
  "bcgov on gold"
check 0 "bcgov-c/something" "https://api.silver.devops.gov.bc.ca:6443" "https://oc-proxy.example" \
  "bcgov-c on silver"
check 1 "bcgov/action-oc-runner" "https://api.gold.devops.gov.bc.ca:6443" "" \
  "empty oc_proxy"
check 1 "otherorg/app" "https://api.gold.devops.gov.bc.ca:6443" "https://oc-proxy.example" \
  "unrelated org on gold"
check 1 "bcgov/action-oc-runner" "https://api.example.com:6443" "https://oc-proxy.example" \
  "bcgov on someone else's cluster"
check 1 "bcgov/action-oc-runner" "https://api.gold.evil.example:6443" "https://oc-proxy.example" \
  "lookalike gold host"
check 1 "bcgov-extra/app" "https://api.gold.devops.gov.bc.ca:6443" "https://oc-proxy.example" \
  "owner prefix must not match"

echo "should_use_proxy_test.sh: ok"
