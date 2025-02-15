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

    # Timeout for cronjob to run; e.g. 5m
    cronjob_timeout: 5m

    # Overrides the default branch to diff against
    diff_branch: ${{ github.event.repository.default_branch }}

    # Override GitHub default oc version >= 4.0
    oc_version: "4.14"

    # Repository to clone and process
    # Useful for consuming other repos, defaults to the current one
    repository: ${{ github.repository }}
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
          oc whofarted
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

The action will return a boolean (true|false) of whether a this action's triggers have fired. It can be useful for follow-up tasks, like running tests or cronjobs.

```yaml
jobs:
  command:
    runs-on: ubuntu-latest
    outputs:
      triggered: ${{ steps.meaningful_step_name.outputs.triggered }}
    steps:
      - id: meaningful_step_name
        uses: bcgov/action-oc-runner@vX.Y.Z
   ...

  result:
    runs-on: ubuntu-latest
    needs: [command]
    steps:
      - needs: [command]
        run: |
          echo "Triggered = ${{ needs.command.outputs.triggered }}
```

# Feedback

Please contribute your ideas!  [Issues] and [pull requests] are appreciated.

<!-- # Acknowledgements

This Action is provided courtesty of the Forestry Digital Services, part of the Government of British Columbia. -->
