# Setting up a Self-Hosted Runner for E2E Tests

This document explains how to set up a self-hosted runner to execute the E2E workflow for this project.  For enhanced security, it's highly recommended to create a dedicated user for the runner and configure passwordless sudo *only* for the specific commands needed by the workflow.  Avoid granting unnecessary privileges to the runner user.

## Prerequisites

- A system with `sudo` access (e.g., a virtual machine or a physical server). If using the same machine where development occurs, be aware that a single self-hosted runner can only execute one workflow job at a time. If multiple workflows are triggered concurrently, they will be queued.  Consider the security implications of running the runner on the same machine as your development environment.
- The system should be able to connect to your GitHub repository.
- The necessary dependencies should be installed on the system. The `bootstrap_env.sh` script can be used to install these dependencies.  However, for improved security, consider installing only the essential dependencies required by the workflow.

## Steps

1. **Create a dedicated user:** Create a dedicated user for the runner. For example:

```bash
sudo useradd github-runner
sudo passwd github-runner
```

2. **Install Dependencies:** Run the `bootstrap_env.sh` script on the self-hosted runner to install the required dependencies:

```bash
sudo ./bootstrap_env.sh
```

This script will install the necessary packages, including Ansible, `yq`, `kcli`, `sshpass`, and other required tools.  You will be prompted for your Red Hat Organization ID and Activation Key during this process.


3. **Configure Passwordless Sudo:** Add the runner user to the sudoers file and configure passwordless sudo.  This is important because the workflow uses sudo for some operations. For example:

```bash
sudo visudo
```

Add the following line, replacing `github-runner` with the actual username:

```
github-runner ALL=(ALL) NOPASSWD: ALL
```


4. **Configure the Self-Hosted Runner:** Follow the instructions in the [GitHub documentation](https://docs.github.com/en/actions/hosting-your-own-runners/adding-self-hosted-runners) to configure the self-hosted runner in your GitHub repository. Configure the runner to run as the dedicated user (e.g., `github-runner`).


5. **Set up Secrets:**  In your GitHub repository settings, under "Secrets and variables" -> "Actions", set the following secrets:

- **`HARBOR_PASSWORD`:** The password for your Harbor registry.

6. **Trigger the Workflow:**  You can now trigger the E2E workflow manually from the "Actions" tab in your GitHub repository.  The workflow will run on the self-hosted runner you've configured.


## Workflow Inputs

The E2E workflow accepts the following inputs:

- **`registry_type`:** The type of registry to use (quay, harbor, or jfrog). Default is quay.
- **`skip_validation`:** Whether to skip environment validation. Set to "yes" or "no". Default is "no".
- **`destroy_vms`:** Whether to destroy VMs after the run. Set to "yes" or "no". Default is "no".

## Additional Notes

- The self-hosted runner should have access to the internet to download the necessary packages and dependencies.
- The `bootstrap_env.sh` script requires `sudo` access to install some of the dependencies.
- Make sure the self-hosted runner has network connectivity to the registry you are using.
- The `run_e2e.sh` script handles the deployment and testing process.  Refer to the script's documentation for more details.
