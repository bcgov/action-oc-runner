<!-- Badges -->
[![Issues](https://img.shields.io/github/issues/bcgov/action-oc-runner)](/../../issues)
[![Pull Requests](https://img.shields.io/github/issues-pr/bcgov/action-oc-runner)](/../../pulls)
[![MIT License](https://img.shields.io/github/license/bcgov/action-oc-runner.svg)](/LICENSE)
[![Lifecycle](https://img.shields.io/badge/Lifecycle-Experimental-339999)](https://github.com/bcgov/repomountie/blob/master/doc/lifecycle-badges.md)

<!-- Reference-Style link -->
[issues]: https://docs.github.com/en/issues/tracking-your-work-with-issues/creating-an-issue
[pull requests]: https://docs.github.com/en/desktop/contributing-and-collaborating-using-github-desktop/working-with-your-remote-repository-on-github-or-github-enterprise/creating-an-issue-or-pull-request

# OpenShift CLI (oc) Login and Runner

Action for running oc commands. Intended for use with the BC Government's OpenShift cluster.  We will do our best to keep the default oc runner version lined up with whatever the platform team currently has deployed to production.

Provide as few as zero commands to login only.  There is a separate parameter for cronjobs, with the ability to report success or failure.

# Usage

```yaml
- uses: bcgov/action-oc-runner@X.Y.Z
  with:
    ### Required
    
    # OpenShift project/namespace
    oc_namespace: abc123-dev

    # OpenShift server
    oc_server: https://api.silver.devops.gov.bc.ca:6443
    
    # OpenShift token
    # Usually available as a secret in your project/namespace
    oc_token: ${{ secrets.OC_TOKEN }}


    ### Typical / recommended

    # Command to run, generally oc commands
    commands: oc whoami

    # Cronjob to run and report on
    cronjob: repo-name-cronjob-etc

    # Bash array to diff for triggering; omit to always run
    triggers: ('frontend/' 'backend/' 'database/')


    ### Usually a bad idea / not recommended

    # Number of cronjob log lines to tail; use -1 for all
    cronjob_tail: 0

    # Overrides the default branch to diff against
    diff_branch: ${{ github.event.repository.default_branch }}

    # Override GitHub default oc version >= 4.0
    oc_version: "4.14"

    # Override repository to clone
    repository: ${{ github.repository }}

    # Override branch, tag or SHA to clone; omit to use the default branch
    ref: ''

    # Timeout for command or cronjob; e.g. 10m
    timeout: 10m

    # Enable verbose command tracing with bash xtrace (set -x)
    verbose: false

    # Maximum number of connection retry attempts for logging into OpenShift
    login_attempts: 5

    # Relay Route to use instead of api.<cluster>:6443, when runner IPs are blocked
    # '{domain}' and '{cluster}' come from oc_server; see relay/openshift.deploy.yml
    oc_relay: https://oc-relay.apps.{domain}

    # Send API traffic through a proxy to change the egress IP the cluster sees.
    # 'tor' installs Tor on the runner; or give an http(s):// or socks5:// URL.
    proxy: ''
```

# Example: Login only

Login only.

```yaml
login:
  name: Login Only
  runs-on: ubuntu-24.04
  steps:
    - uses: bcgov/action-oc-runner@X.Y.Z
      with:
        oc_namespace: ${{ vars.oc_namespace }}
        oc_server: ${{ vars.oc_server }}
        oc_token: ${{ secrets.OC_TOKEN }}
```

# Example: Run Multiple Commands Conditionally (w/ Triggers)

Run multiple commands if any trigger files/paths have changes.  Triggers are optional.

```yaml
whoareyou:
  name: Who Are You?
  runs-on: ubuntu-24.04
  steps:
    - uses: bcgov/action-oc-runner@X.Y.Z
      with:
        oc_namespace: ${{ vars.oc_namespace }}
        oc_server: ${{ vars.oc_server }}
        oc_token: ${{ secrets.OC_TOKEN }}
        triggers: ('frontend/' 'backend/' 'database/')
        commands: |
          oc whoami
          oc version
```

# Example: Run and Report on Cronjob (w/ Triggers)

Provide the name of a cronjob object.  It will be run timestamped and return a success or failure on completion.  Triggers are optional.

```yaml
cronjob:
  name: Run and Report on Cronjob
  runs-on: ubuntu-24.04
  steps:
    - uses: bcgov/action-oc-runner@X.Y.Z
      with:
        oc_namespace: ${{ vars.oc_namespace }}
        oc_server: ${{ vars.oc_server }}
        oc_token: ${{ secrets.OC_TOKEN }}
        triggers: ('cronjobland/' 'misc/' 'whatever/')
        cronjob: repo-name-cronjob-etc
```

# Output

This action returns:

- `triggered`: boolean (`'true'` or `'false'`) indicating whether trigger paths changed
- `commands`: generic command output channel from the `commands` step (usually empty unless explicitly set)

`commands` is expected to be empty in most runs. To populate it, write to `$GITHUB_OUTPUT` inside your `commands` input. Plain text lines are automatically mapped to the `commands` output (you do not need to prefix with `commands=`). Existing `commands=<value>` usage is still supported.

```yaml
jobs:
  command:
    runs-on: ubuntu-latest
    outputs:
      triggered: ${{ steps.oc.outputs.triggered }}
      commands: ${{ steps.oc.outputs.commands }}
    steps:
      - id: oc
        uses: bcgov/action-oc-runner@vX.Y.Z
        with:
          oc_namespace: ${{ vars.oc_namespace }}
          oc_server: ${{ vars.oc_server }}
          oc_token: ${{ secrets.OC_TOKEN }}
          commands: |
            oc whoami
            echo "$(oc whoami)" >> "$GITHUB_OUTPUT"

  result:
    runs-on: ubuntu-latest
    needs: [command]
    steps:
      - run: |
          echo "Triggered = ${{ needs.command.outputs.triggered }}"
          echo "Command output = ${{ needs.command.outputs.commands }}"
```

# Blocked runner IPs and the API relay

GitHub-hosted runners get rotating Azure IPs. When a cluster drops some of those, login fails with `HTTP 000` / `curl: (28)` on every attempt, because all retries reuse the same runner IP. The cluster API itself is reachable from the public internet, so only the runner's source address is the problem.

The relay is an nginx reverse proxy that runs **on the cluster** and forwards to the in-cluster API (`kubernetes.default.svc`). GitHub talks to a normal Route on `*.apps.<cluster>` port 443 instead of `api.<cluster>` port 6443. It holds no credentials and passes your `Authorization` header straight through, and it can only reach its own cluster's API, so it is not an open proxy.

Each cluster needs its own relay, because a relay only ever talks to the API of the cluster it runs on. Deploy one per cluster from a machine that can already reach that cluster, such as a laptop:

```bash
oc process -f relay/openshift.deploy.yml \
  -p HOST=oc-relay.apps.silver.devops.gov.bc.ca | oc apply -f -

oc process -f relay/openshift.deploy.yml \
  -p HOST=oc-relay.apps.gold.devops.gov.bc.ca | oc apply -f -

oc process -f relay/openshift.deploy.yml \
  -p HOST=oc-relay.apps.emerald.devops.gov.bc.ca | oc apply -f -
```

```yaml
- uses: bcgov/action-oc-runner@X.Y.Z
  with:
    oc_namespace: ${{ vars.oc_namespace }}
    oc_server: ${{ vars.oc_server }}
    oc_token: ${{ secrets.OC_TOKEN }}
    oc_relay: https://oc-relay.apps.{domain}
    commands: oc whoami
```

OpenShift names its API `api.<cluster>.<domain>` and its routes `*.apps.<cluster>.<domain>`, so both placeholders come from `oc_server` and a single `oc_relay` value works on any cluster, in any organization:

| Placeholder | `https://api.silver.devops.gov.bc.ca:6443` gives |
| :--- | :--- |
| `{domain}` | `silver.devops.gov.bc.ca` |
| `{cluster}` | `silver` |

Callers keep passing the `oc_server` they already pass. Use a plain hostname with no placeholder to pin one fixed relay.

**Access control:** the relay deliberately has none of its own. Every request already carries your OpenShift token, which the cluster API validates, and the relay cannot reach anything except that one API. Adding a second credential would mean either editing every calling repository (composite actions cannot read the `secrets` context) or hardcoding one organization's identity provider into a shared action.

**Rolling this out to many repositories:** set the `oc_relay` default in `action.yml` and tag a release. Dependents that never pass `oc_relay` pick it up on their next Renovate bump, with no change to their workflow files. The default ships empty, so nothing routes through a relay until you deploy one and set it.

## Changing the egress IP with no infrastructure

If you do not want to run a relay, `proxy: tor` installs and starts Tor on the runner and sends `curl` and `oc` through it. The cluster then sees a Tor exit address instead of the blocked runner IP. It is free, needs nothing deployed, and costs roughly 30 seconds of setup per job.

```yaml
- uses: bcgov/action-oc-runner@X.Y.Z
  with:
    oc_namespace: ${{ vars.oc_namespace }}
    oc_server: ${{ vars.oc_server }}
    oc_token: ${{ secrets.OC_TOKEN }}
    proxy: tor
    commands: oc whoami
```

`proxy` also takes a URL if you have your own hop, for example `http://oc-proxy.example:3128` or `socks5://oc-proxy.example:1080`. Credentials in the URL are rejected, and GitHub and `mirror.openshift.com` always stay direct.

**The proxy is untrusted by design.** TLS runs end to end between the runner and the cluster API, so a proxy operator sees only ciphertext and the hostname, never your OpenShift token. This holds only because the token request validates the API certificate; do not reintroduce `curl -k`, which would let any proxy present its own certificate and read the token in plain text.

Two caveats worth testing before you rely on Tor: many government networks block Tor exit addresses outright, so this may trade one block for another, and exit IPs change per circuit, so it cannot be combined with an allowlist.

# OpenShift Login Retry and Fail-Fast Behavior

To handle transient network drops, cluster API restarts, or runner configuration mistakes, the action implements validation gates and retry logic:
- **Early Input Validation:** Before executing any login attempts or downloading tools, the action validates that `oc_server`, `oc_namespace`, and `oc_token` are populated and that the server URL is properly formatted. If inputs are missing or malformed, the action fails fast immediately to prevent useless retries.
- **Fail Fast:** If the OpenShift API returns a non-retryable client error (such as `401 Unauthorized`, `403 Forbidden`, or `404 Not Found`), the action aborts immediately on the first attempt to save runner billing minutes.
- **Retry:** If the connection times out at the network layer (HTTP status `000`), hits a request timeout (`408`), gets rate-limited (`429`), or if the API returns a transient server error (HTTP status `5xx` during control-plane reboots), the action sleeps with exponential backoff (starting at 2 seconds) and retries up to `login_attempts` times.
- **CLI Download Timeout:** Download of the `oc` CLI client archive from `mirror.openshift.com` is capped with a 15-second timeout and 3 retry attempts to prevent workflows from hanging indefinitely.

# Troubleshooting

The `commands` block runs in strict shell mode. A command failure (including optional `grep` misses in pipelines) can stop the step immediately.

- For optional matches, use guards like `grep ... || true`
- Prefer explicit conditional checks when an empty result is valid
- Set `verbose: true` to enable `set -x` tracing for the `commands` block and internal output processing; enable it temporarily and only when you are confident sensitive values will not be printed

## Safe Debugging

When `verbose: true` is enabled, shell tracing may show expanded command arguments, environment usage, and command output in logs. GitHub masks known secrets, but derived or partial secret values can still leak. Use this mode only for short-lived troubleshooting and avoid commands that print or interpolate sensitive values.

# Feedback

Please contribute your ideas!  [Issues] and [pull requests] are appreciated.

<!-- # Acknowledgements

This Action is provided courtesty of the Forestry Digital Services, part of the Government of British Columbia. -->
