#!/usr/bin/env bash
# Decide whether this login may use the CONNECT proxy, and which host.
# Only bcgov and bcgov-c workflows talking to gold or silver may; everyone
# else connects directly. Callers do not set oc_proxy: empty means the
# Silver proxy. A non-empty OC_PROXY is an override (CI, tests).
#
# Exit 0: prints the proxy URL on stdout.
# Exit 1: prints a skip reason on stderr.
set -euo pipefail

owner="${GITHUB_REPOSITORY%%/*}"
if [ "${owner}" != "bcgov" ] && [ "${owner}" != "bcgov-c" ]; then
  echo "Repository '${GITHUB_REPOSITORY}' is not in bcgov or bcgov-c; skipping proxy" >&2
  exit 1
fi

host=""
if [[ "${OC_SERVER}" =~ ^https://([A-Za-z0-9._-]+):6443/?$ ]]; then
  host="${BASH_REMATCH[1]}"
fi

if [ "${host}" != "api.gold.devops.gov.bc.ca" ] && [ "${host}" != "api.silver.devops.gov.bc.ca" ]; then
  echo "oc_server '${OC_SERVER}' is not gold or silver; skipping proxy" >&2
  exit 1
fi

if [ -n "${OC_PROXY:-}" ]; then
  echo "${OC_PROXY}"
  exit 0
fi

# One proxy, in Silver. It CONNECTs to either API; gold does not need its own.
echo "https://oc-proxy.apps.silver.devops.gov.bc.ca"
