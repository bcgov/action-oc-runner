<!-- Badges -->
[![Issues](https://img.shields.io/github/issues/bcgov/action-conditional-container-builder)](/../../issues)
[![Pull Requests](https://img.shields.io/github/issues-pr/bcgov/action-conditional-container-builder)](/../../pulls)
[![MIT License](https://img.shields.io/github/license/bcgov/action-conditional-container-builder.svg)](/LICENSE)
[![Lifecycle](https://img.shields.io/badge/Lifecycle-Experimental-339999)](https://github.com/bcgov/repomountie/blob/master/doc/lifecycle-badges.md)

<!-- Reference-Style link -->
[issues]: https://docs.github.com/en/issues/tracking-your-work-with-issues/creating-an-issue
[pull requests]: https://docs.github.com/en/desktop/contributing-and-collaborating-using-github-desktop/working-with-your-remote-repository-on-github-or-github-enterprise/creating-an-issue-or-pull-request

# OpenShift CLI (oc) Login and Runner

Action for running oc commands. Version can be updated in one spot when the platform team updates OpenShift.

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

    # Bash array to diff for triggering; omit to always run
    triggers: ('frontend/' 'backend/' 'database/')


    ### Usually a bad idea / not recommended

    # Override GitHub default oc version >= 4.0
    oc_version: "4.14"
```

# Example, Single Command with Login

Run a single command.

```yaml
whoami:
  name: Who Am I?
  runs-on: ubuntu-24.04
  steps:
    - uses: bcgov/action-oc-runner@X.Y.Z
      with:
        commands: oc whoami
        oc_namespace: ${{ secrets.OC_NAMESPACE }}
        oc_server: ${{ secrets.OC_SERVER }}
        oc_token: ${{ secrets.OC_TOKEN }}
```

# Example, Run Multiple Commands with a Trigger

Run multiple commands if a trigger is fired.

```yaml
whoami:
  name: Who Am I?
  runs-on: ubuntu-24.04
  steps:
    - uses: bcgov/action-oc-runner@X.Y.Z
      with:
        oc_namespace: ${{ secrets.OC_NAMESPACE }}
        oc_server: ${{ secrets.OC_SERVER }}
        oc_token: ${{ secrets.OC_TOKEN }}
        triggers: ('frontend/' 'backend/' 'database/')
        commands: |
          oc whoami
          oc version
          oc whofarted
```

# Example, Login only

Login only.

```yaml
whoami:
  name: Login
  runs-on: ubuntu-24.04
  steps:
    - uses: bcgov/action-oc-runner@X.Y.Z
      with:
        oc_namespace: ${{ secrets.OC_NAMESPACE }}
        oc_server: ${{ secrets.OC_SERVER }}
        oc_token: ${{ secrets.OC_TOKEN }}
```

# Example, Legacy binary

Run a single command.

```yaml
whoami:
  name: Login
  runs-on: ubuntu-24.04
  steps:
    - uses: bcgov/action-oc-runner@X.Y.Z
      with:
        commands: oc version
        oc_namespace: ${{ secrets.OC_NAMESPACE }}
        oc_server: ${{ secrets.OC_SERVER }}
        oc_token: ${{ secrets.OC_TOKEN }}
        oc_version: '4.1'
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
