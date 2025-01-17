<!-- Badges -->
[![Issues](https://img.shields.io/github/issues/bcgov-nr/action-conditional-container-builder)](/../../issues)
[![Pull Requests](https://img.shields.io/github/issues-pr/bcgov-nr/action-conditional-container-builder)](/../../pulls)
[![MIT License](https://img.shields.io/github/license/bcgov-nr/action-conditional-container-builder.svg)](/LICENSE)
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


    ### Usually a bad idea / not recommended

    # Override GitHub default oc version
    oc_version: "4.14"
```

# Example, Single Command with Login

Run a single command.

```yaml
whoami:
  name: Who Am I?
  runs-on: ubuntu-latest
  steps:
    - uses: bcgov/action-oc-runner@X.Y.Z
      with:
        commands: oc whoami
        oc_namespace: ${{ secrets.OC_NAMESPACE }}
        oc_server: ${{ secrets.OC_SERVER }}
        oc_token: ${{ secrets.OC_TOKEN }}
        oc_version: '3'
```

# Example, Login only

Run a single command.

```yaml
whoami:
  name: Login
  runs-on: ubuntu-latest
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
  runs-on: ubuntu-latest
  steps:
    - uses: bcgov/action-oc-runner@X.Y.Z
      with:
        commands: oc version
        oc_namespace: ${{ secrets.OC_NAMESPACE }}
        oc_server: ${{ secrets.OC_SERVER }}
        oc_token: ${{ secrets.OC_TOKEN }}
```


# Feedback

Please contribute your ideas!  [Issues] and [pull requests] are appreciated.

<!-- # Acknowledgements

This Action is provided courtesty of the Forestry Digital Services, part of the Government of British Columbia. -->
