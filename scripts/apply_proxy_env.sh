# Apply optional ACTION_PROXY to curl/oc. Source this file; do not execute.
# Empty ACTION_PROXY is a no-op. 'tor' starts Tor on the runner. Otherwise the value
# is a proxy URL; credentials, paths, and query strings are rejected.

if [ -n "${ACTION_PROXY:-}" ]; then
  if [ "${ACTION_PROXY}" = "tor" ]; then
    _proxy_url="$("$(dirname "${BASH_SOURCE[0]}")/start_tor.sh")" || return 1
  elif [[ "${ACTION_PROXY}" =~ ^(https?|socks5)://[A-Za-z0-9._-]+(:[0-9]{1,5})?$ ]]; then
    _proxy_url="${ACTION_PROXY}"
  else
    echo "::error::Invalid proxy '${ACTION_PROXY}'. Use 'tor', or http(s)://host[:port] or socks5://host[:port] with no credentials, path, or query."
    if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
      return 1
    fi
    exit 1
  fi

  export HTTP_PROXY="${_proxy_url}"
  export HTTPS_PROXY="${_proxy_url}"
  export http_proxy="${_proxy_url}"
  export https_proxy="${_proxy_url}"
  export ALL_PROXY="${_proxy_url}"
  export all_proxy="${_proxy_url}"
  export NO_PROXY="localhost,127.0.0.1,github.com,.github.com,api.github.com,githubusercontent.com,.githubusercontent.com,ghcr.io,mirror.openshift.com"
  export no_proxy="${NO_PROXY}"

  # Hand the settings to later steps. This file lives beside action.yml, which a
  # non-default 'repository' checkout replaces in the workspace, so it cannot be
  # sourced again once the commands step runs.
  if [ -n "${GITHUB_ENV:-}" ]; then
    for _var in HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy; do
      echo "${_var}=${!_var}" >> "${GITHUB_ENV}"
    done
    unset _var
  fi

  echo "OpenShift API traffic will use proxy ${_proxy_url}"
  unset _proxy_url
fi
