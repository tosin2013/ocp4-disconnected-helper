# Setting up a Self-Hosted Runner for E2E Tests (RHEL 9.5)

This document explains how to set up a self-hosted runner on a Red Hat Enterprise Linux 9.5 system to execute the E2E workflow for this project.  The runner will operate as the `lab-user` for consistency and access to project resources. Fotk this repository, the runner will be configured to run as the `lab-user`.

## Prerequisites

- A Red Hat Enterprise Linux 9.5 system with `sudo` access.
- A valid Red Hat subscription with an Organization ID and Activation Key. If you don't have these, follow these steps: [Link to Red Hat documentation]

## Steps

1. **Install Dependencies:** Run the `bootstrap_env.sh` script on the self-hosted runner to install the required dependencies:

```bash
sudo ./bootstrap_env.sh
```

This script will install the necessary packages, including Ansible, `kcli`, and other required tools.  You will be prompted for your Red Hat Organization ID and Activation Key during this process. It also sets up a storage pool named `kvm_pool`.

2. **Create the Runner Directory:** Create a directory for the runner and give ownership to the lab-user:

```bash
cd ~
sudo mkdir actions-runner && sudo chown lab-user:users actions-runner
```

3. **Download and Extract the Runner Package:** As the lab-user, download and extract the latest runner package:

```bash
$ cd actions-runner
$ curl -o actions-runner-linux-x64-2.322.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.322.0/actions-runner-linux-x64-2.322.0.tar.gz
$ echo "b13b784808359f31bc79b08a191f5f83757852957dd8fe3dbfcc38202ccf5768  actions-runner-linux-x64-2.322.0.tar.gz" | shasum -a 256 -c
$ tar xzf ./actions-runner-linux-x64-2.322.0.tar.gz
$  ./config.sh --url https://github.com/tosin2013/ocp4-disconnected-helper --token TOKEN

--------------------------------------------------------------------------------
|        ____ _ _   _   _       _          _        _   _                      |
|       / ___(_) |_| | | |_   _| |__      / \   ___| |_(_) ___  _ __  ___      |
|      | |  _| | __| |_| | | | | '_ \    / _ \ / __| __| |/ _ \| '_ \/ __|     |
|      | |_| | | |_|  _  | |_| | |_) |  / ___ \ (__| |_| | (_) | | | \__ \     |
|       \____|_|\__|_| |_|\__,_|_.__/  /_/   \_\___|\__|_|\___/|_| |_|___/     |
|                                                                              |
|                       Self-hosted runner registration                        |
|                                                                              |
--------------------------------------------------------------------------------

# Authentication


√ Connected to GitHub

# Runner Registration

Enter the name of the runner group to add this runner to: [press Enter for Default] 

Enter the name of runner: [press Enter for hypervisor] self-hosted

This runner will have the following labels: 'self-hosted', 'Linux', 'X64' 
Enter any additional labels (ex. label-1,label-2): [press Enter to skip] 

√ Runner successfully added
√ Runner connection is good

# Runner settings

Enter name of work folder: [press Enter for _work] /home/lab-user/ocp4-disconnected-helper

√ Settings Saved.

[lab-user@hypervisor actions-runner]$ sudo ./svc.sh install
Creating launch runner in /etc/systemd/system/actions.runner.tosin2013-ocp4-disconnected-helper.self-hosted.service
Run as user: lab-user
Run as uid: 1000
gid: 100
Created symlink /etc/systemd/system/multi-user.target.wants/actions.runner.tosin2013-ocp4-disconnected-helper.self-hosted.service → /etc/systemd/system/actions.runner.tosin2013-ocp4-disconnected-helper.self-hosted.service.
[lab-user@hypervisor actions-runner]$ sudo ./svc.sh start

/etc/systemd/system/actions.runner.tosin2013-ocp4-disconnected-helper.self-hosted.service
● actions.runner.tosin2013-ocp4-disconnected-helper.self-hosted.service - GitHub Actions Runner (tosin2013-ocp4-disconnected-helper.self-hosted)
     Loaded: loaded (/etc/systemd/system/actions.runner.tosin2013-ocp4-disconnected-helper.self-hosted.service; enabled; preset: disabled)
     Active: active (running) since Mon 2025-02-10 10:36:46 EST; 9ms ago
   Main PID: 49439 (runsvc.sh)
      Tasks: 2 (limit: 2467099)
     Memory: 1.5M
        CPU: 6ms
     CGroup: /system.slice/actions.runner.tosin2013-ocp4-disconnected-helper.self-hosted.service
             ├─49439 /bin/bash /home/lab-user/actions-runner/runsvc.sh
             └─49443 ./externals/node20/bin/node ./bin/RunnerService.js

Feb 10 10:36:46 hypervisor systemd[1]: Started GitHub Actions Runner (tosin2013-ocp4-disconnected-helper.self-hosted).
Feb 10 10:36:46 hypervisor runsvc.sh[49439]: .path=/home/lab-user/.cursor-server/cli/servers/Stable-f5f18731406b73244e0558ee7716d77c8096d150/server/bin/remote-cli:/home/lab-user/.…/sbin:/usr/sbin
Hint: Some lines were ellipsized, use -l to show in full.
```

4. **Configure the Runner:** Follow the instructions in the [GitHub documentation](https://docs.github.com/en/actions/hosting-your-own-runners/adding-self-hosted-runners) to configure the self-hosted runner in your GitHub repository.  Configure the runner to run as the `lab-user`.

5. **Set up Secrets:**  In your GitHub repository settings, under "Secrets and variables" -> "Actions", set the following secrets:

- **`HARBOR_PASSWORD`:** The password for your Harbor registry.

6. **Run Validation Script:** After setting up the runner, run the `validate_env.sh` script to ensure everything is configured correctly:

```bash
./validate_env.sh
```

## Workflow Inputs

The E2E workflow accepts the following inputs:

- **`registry_type`:** The type of registry to use (quay, harbor, or jfrog). Default is quay.
- **`skip_validation`:** Whether to skip environment validation. Set to "yes" or "no". Default is "no".
- **`destroy_vms`:** Whether to destroy VMs after the run. Set to "yes" or "no". Default is "no".

## Additional Notes

- The self-hosted runner should have access to the internet to download the necessary packages and dependencies.
- Ensure the `lab-user` has appropriate permissions to access and execute the project files and scripts.
- Make sure the self-hosted runner has network connectivity to the registry you are using.
- The `run_e2e.sh` script handles the deployment and testing process.  Refer to the script's documentation for more details.
