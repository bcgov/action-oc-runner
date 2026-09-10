# Apply optional ACTION_HTTPS_PROXY to curl/oc. Source this file; do not execute.
# Empty ACTION_HTTPS_PROXY is a no-op. Credentials, paths, and query strings are rejected.

if [ -n "${ACTION_HTTPS_PROXY:-}" ]; then
  if [[ ! "${ACTION_HTTPS_PROXY}" =~ ^https?://[A-Za-z0-9._-]+(:[0-9]{1,5})?$ ]]; then
    echo "::error::Invalid https_proxy '${ACTION_HTTPS_PROXY}'. Use http(s)://host or http(s)://host:port with no credentials, path, or query."
    if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
      return 1
    fi
    exit 1
  fi
  export HTTP_PROXY="${ACTION_HTTPS_PROXY}"
  export HTTPS_PROXY="${ACTION_HTTPS_PROXY}"
  export http_proxy="${ACTION_HTTPS_PROXY}"
  export https_proxy="${ACTION_HTTPS_PROXY}"
  export NO_PROXY="localhost,127.0.0.1,github.com,.github.com,api.github.com,githubusercontent.com,.githubusercontent.com,ghcr.io,mirror.openshift.com"
  export no_proxy="${NO_PROXY}"
  echo "OpenShift API traffic will use HTTP CONNECT proxy ${ACTION_HTTPS_PROXY}"
fi
