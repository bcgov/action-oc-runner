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

# OpenShift Login Retry and Fail-Fast Behavior

To handle transient network drops, cluster API restarts, or runner configuration mistakes, the action implements validation gates and retry logic:
- **Early Input Validation:** Before executing any login attempts or downloading tools, the action validates that `oc_server`, `oc_namespace`, and `oc_token` are populated and that the server URL is properly formatted. If inputs are missing or malformed, the action fails fast immediately to prevent useless retries.
- **Fail Fast:** If the OpenShift API returns a non-retryable client error (such as `401 Unauthorized`, `403 Forbidden`, or `404 Not Found`), the action aborts immediately on the first attempt to save runner billing minutes.
- **Retry:** If the connection times out at the network layer (HTTP status `000`), hits a request timeout (`408`), gets rate-limited (`429`), or if the API returns a transient server error (HTTP status `5xx` during control-plane reboots), the action sleeps with exponential backoff (starting at 2 seconds) and retries up to `login_attempts` times.
- **CLI Download Timeout:** Download of the `oc` CLI client archive from `mirror.openshift.com` is capped with a 15-second timeout and 3 retry attempts to prevent workflows from hanging indefinitely.

# Blocked Runner IPs (oc_proxy)

GitHub-hosted runners are sometimes unable to reach the OpenShift API, failing login with `curl: (28)` timeouts while the same cluster answers normally from elsewhere. The address the runner happens to get is blocked upstream, and neither the workflow nor this action can choose a different one.

`oc_proxy` tunnels API traffic through a CONNECT proxy, so the cluster sees the proxy's address instead of the runner's:

```yaml
- uses: bcgov/action-oc-runner@vX.Y.Z
  with:
    oc_namespace: ${{ vars.oc_namespace }}
    oc_server: ${{ vars.oc_server }}
    oc_token: ${{ secrets.oc_token }}
    oc_proxy: https://oc-proxy.apps.silver.devops.gov.bc.ca
    commands: oc whoami
```

The action only arms that proxy for workflows in `bcgov` or `bcgov-c` whose `oc_server` is gold or silver (`api.gold.devops.gov.bc.ca` or `api.silver.devops.gov.bc.ca`). Any other caller connects directly, including an unrelated org that copied `oc_proxy` from a sample, and including a bcgov workflow pointed at some other cluster.

No new secret is needed. The action authenticates to the proxy with the calling workflow's `GITHUB_TOKEN`, passed as `owner/repo` plus token in the proxy URL.

The proxy works out which repository a token belongs to rather than believing the name it was given. It asks `https://api.github.com/installation/repositories`, which reports the repositories a workflow token is scoped to, and accepts the request only if the claimed repository is among them. Checking `/repos/<claimed-repo>` instead would prove nothing, because every valid token can read any public repository, so that check would admit anyone with a GitHub account.

This means `oc_proxy` needs the workflow's own `GITHUB_TOKEN`, which is the default. A personal access token is not an installation token and will be refused.

Because it tunnels with `CONNECT`, TLS runs end-to-end between the runner and the cluster. **The proxy never sees your OpenShift token**, only encrypted bytes. It also refuses anything that is not a `CONNECT` to a declared API host on port 6443, so an authorized caller cannot use it as a general-purpose proxy.

## Running the proxy

`proxy/` holds everything needed: a squid config, the GitHub auth helper, a `Containerfile`, and an OpenShift template. Pushes to `main` that touch `proxy/` publish `ghcr.io/bcgov/action-oc-runner/oc-connect-proxy`, tagged `latest` and by commit SHA, but only after the access gate passes. The package starts private, so either make it public or give the namespace a pull secret.

```bash
oc process -f proxy/openshift.deploy.yml \
  -p HOST=oc-proxy.apps.silver.devops.gov.bc.ca \
  -p TLS_SECRET=oc-proxy-tls \
  -p IMAGE=ghcr.io/bcgov/action-oc-runner/oc-connect-proxy:latest \
  -p OWNER_REGEX='^bcgov(-c)?/' | oc apply -f -
```

`OWNER_REGEX` and `API_HOSTS` are how the *deployed proxy* decides who it will tunnel. The action has a separate, stricter gate: it never sends traffic there unless the caller is `bcgov` or `bcgov-c` and the target is gold or silver. The Route is passthrough because squid terminates TLS itself, which it must: proxy credentials are base64-encoded rather than encrypted, so a cleartext port would expose `GITHUB_TOKEN`s.

Host it wherever is reachable. In-cluster keeps it under your control; anywhere with a stable address also works, and the proxy's blindness to OpenShift tokens is what makes that acceptable.

`bash proxy/proxy_test.sh` builds the image and checks the gate against a fake GitHub and a fake API, so it needs no cluster or real credentials.

## Limits

This restricts use to an *organization*, not to this action. GitHub issues no identity for a composite action, and this repository is public, so any check tied to the action's own code could be reproduced by copying it. Organization membership is the strongest claim that can actually be verified.

The proxy does receive repo-scoped `GITHUB_TOKEN`s, valid for the length of a job. Run it somewhere you trust.

There is no rate limiting. Every unrecognised credential costs one GitHub API call, and validated ones are cached for 30 minutes, so a flood of bogus credentials can saturate the eight auth helpers and slow logins. It degrades rather than opens up, but put rate limiting in front of it if that matters.

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
