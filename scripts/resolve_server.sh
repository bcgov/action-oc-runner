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

# OpenShift names its API api.<cluster>.<domain> and its routes *.apps.<cluster>.<domain>,
# so both placeholders come from oc_server and work on any cluster:
#   {cluster} -> silver                    the label after 'api.'
#   {domain}  -> silver.devops.gov.bc.ca   everything after 'api.', minus the port
CLUSTER=""
DOMAIN=""
if [[ "${OC_SERVER}" =~ ^https://api\.(([a-z0-9-]+)\.[A-Za-z0-9.-]+?)(:[0-9]+)?/?$ ]]; then
  DOMAIN="${BASH_REMATCH[1]}"
  CLUSTER="${BASH_REMATCH[2]}"
fi

if [[ "${OC_RELAY}" == *"{"* ]] && [ -z "${DOMAIN}" ]; then
  echo "::error::oc_relay uses a placeholder but oc_server '${OC_SERVER}' is not https://api.<cluster>.<domain>:6443. Set oc_relay to a full host or pass oc_relay: '' to connect directly." >&2
  exit 1
fi

RESOLVED="${OC_RELAY//\{domain\}/${DOMAIN}}"
echo "${RESOLVED//\{cluster\}/${CLUSTER}}"
