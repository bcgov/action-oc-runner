#!/usr/bin/env bash
# Whether this login may use oc_proxy. Only bcgov and bcgov-c workflows talking
# to gold or silver may; everyone else connects directly, including callers who
# copied oc_proxy from a sample workflow.
#
# Exit 0 = arm the proxy. Exit 1 = skip it. Always prints one line of reason.
set -euo pipefail

if [ -z "${OC_PROXY:-}" ]; then
  echo "oc_proxy is empty; connecting directly"
  exit 1
fi

owner="${GITHUB_REPOSITORY%%/*}"
if [ "${owner}" != "bcgov" ] && [ "${owner}" != "bcgov-c" ]; then
  echo "Repository '${GITHUB_REPOSITORY}' is not in bcgov or bcgov-c; skipping proxy"
  exit 1
fi

host=""
if [[ "${OC_SERVER}" =~ ^https://([A-Za-z0-9._-]+):6443/?$ ]]; then
  host="${BASH_REMATCH[1]}"
fi

if [ "${host}" != "api.gold.devops.gov.bc.ca" ] && [ "${host}" != "api.silver.devops.gov.bc.ca" ]; then
  echo "oc_server '${OC_SERVER}' is not gold or silver; skipping proxy"
  exit 1
fi

echo "Proxy allowed for ${GITHUB_REPOSITORY} -> ${host}"
exit 0
