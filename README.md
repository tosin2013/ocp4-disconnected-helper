# OpenShift 4 Disconnected Helper

This repository provides some automation and other utilities to deploy OpenShift in a disconnected environment.

Currently supports the following patterns:

1. **Downloading OpenShift releases to a local directory and package as a TAR file.**  This is intended to be done in a network with WAN access or a via a DMZ host.
2. **Extracting that TAR file to a directory, and pushing to a registry.**  Once the TAR has been transported from the DMZ to a disconnected/secure enclave, you would extract it and push to a local registry to be used for installation.
3. Setting up a local Docker Registry.

## 1. Download OpenShift Releases and Operator Catalog to a local directory and package as a TAR file

1. Modify the `inventory` file under the `dmzMirror` group to reflect the host that is running the mirroring process.  If you're running this via the CLI on the same node in the DMZ then just modify to run as a localhost entry.
2. Download a Red Hat Registry Pull Secret and save it to a file: https://cloud.redhat.com/openshift/install/pull-secret
   1. Optionally, if running via Tower or storing the Pull Secret as a Vaulted variable, you can define the Pull Secret in a variable called `rh_pull_secret` with the content wrapped in a single quote.
3. Configure any additional variables for what to mirror - by default it mirrors OpenShift 4.12.15 with a set of additional releases to upgrade to 4.13.10 with the shortest path.  A set of Operators are also set as defaults that should work for many bare metal deployments.

> You can specify Operators to mirror simply by their package name from the target Operator Catalog - unless specified, the automation will determine the default channel to mirror.

```bash=
# Run the automation
ansible-playbook -i inventory download-to-tar.yml
```

## Helpful Commands

### List Operators in an Operator Catalog

```bash=
# List all the available Operator Catalogs for a specific OpenShift release
oc mirror list operators --version=4.13

# List the Operators in the Operator Indexes
oc mirror list operators --catalog=registry.redhat.io/redhat/redhat-operator-index:v4.13
oc mirror list operators --catalog=registry.redhat.io/redhat/certified-operator-index:v4.13
oc mirror list operators --catalog=registry.redhat.io/redhat/community-operator-index:v4.13
oc mirror list operators --catalog=registry.redhat.io/redhat/redhat-marketplace-index:v4.13

# List all channels in an operator package
oc-mirror list operators --catalog=registry.redhat.io/redhat/redhat-operator-index:v4.13 --package=cincinnati-operator
```