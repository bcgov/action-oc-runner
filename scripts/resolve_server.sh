#!/usr/bin/env bash
# Print the API URL to use. With OC_RELAY set, substitute {cluster} from OC_SERVER
# and return the relay Route instead of the cluster's public API endpoint.
set -euo pipefail

if [ -z "${OC_RELAY:-}" ]; then
  echo "${OC_SERVER}"
  exit 0
fi

if [[ ! "${OC_RELAY}" =~ ^https://[A-Za-z0-9._{}-]+$ ]]; then
  echo "::error::Invalid oc_relay '${OC_RELAY}'. Use an https:// host, optionally containing {cluster}." >&2
  exit 1
fi

# Cluster name is the label after 'api.', e.g. silver, gold or emerald
CLUSTER=""
if [[ "${OC_SERVER}" =~ ^https://api\.([a-z0-9-]+)\. ]]; then
  CLUSTER="${BASH_REMATCH[1]}"
fi

if [[ "${OC_RELAY}" == *"{cluster}"* ]] && [ -z "${CLUSTER}" ]; then
  echo "::error::oc_relay contains {cluster} but oc_server '${OC_SERVER}' is not https://api.<cluster>.<domain>:6443. Set oc_relay to a full host or pass oc_relay: '' to connect directly." >&2
  exit 1
fi

echo "${OC_RELAY//\{cluster\}/${CLUSTER}}"
