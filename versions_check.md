#### How to Run the `versions_check.sh` Script

1. **Ensure Dependencies are Installed**:
   - Install `curl`, `jq`, and `yq` if not already installed.
   ```bash
   sudo yum install curl jq
   ```

2. **Run the Script**:
   - Execute the script from the terminal.
   ```bash
   ./versions_check.sh
   ```

3. **Optional**:
   - Use the `--skip-update` flag to skip the prompt for updating versions in `extra_vars/download-to-tar-vars.yml`.
   ```bash
   ./versions_check.sh --skip-update
   ```

#### Important Information

- **Root Privileges**: The script checks for root privileges and uses `sudo` if necessary.
- **API Access**: The script accesses the OpenShift upgrades information API to fetch release data. Ensure network connectivity and API availability.
- **Version Update**: The script can update the versions in `extra_vars/download-to-tar-vars.yml` based on user input.

#### Example Output

```bash
Recent 4.15 releases:
4.15.1
4.15.2
4.15.3

Recent 4.16 releases:
4.16.1
4.16.2
4.16.3

Fetching the two latest minor versions...
Latest minor versions: 4.15, 4.16
Fetching the latest patch versions for 4.15 and 4.16...
Fetching latest 4.16 release...
Latest 4.15 release: 4.15.3
Latest 4.16 release: 4.16.3

Release information for 4.15.3:
{
  "version": "4.15.3",
  "releaseCreation": "2023-01-01T00:00:00Z",
  "displayVersion": "4.15.3"
}

Release information for 4.16.3:
{
  "version": "4.16.3",
  "releaseCreation": "2023-01-02T00:00:00Z",
  "displayVersion": "4.16.3"
}

Checking upgrade path from 4.15.3 to 4.16.3
{
  "version": "4.15.3",
  "release": "quay.io/openshift-release-dev/ocp-release@sha256:abc123"
}
{
  "version": "4.16.3",
  "release": "quay.io/openshift-release-dev/ocp-release@sha256:def456"
}

Would you like to update the versions in extra_vars/download-to-tar-vars.yml? (y/n): y
Versions updated in extra_vars/download-to-tar-vars.yml
```

#### Additional Notes

- **Script Execution**: The script is designed to be run in a Bash environment. Ensure that the script has execute permissions.
  ```bash
  chmod +x versions_check.sh
  ```

- **Error Handling**: The script includes basic error handling for API requests. If the API request fails, it will print an error message and return a non-zero exit code.

- **Configuration File**: The script updates the `extra_vars/download-to-tar-vars.yml` file with the latest versions. Ensure that this file is correctly configured and accessible.

- **Dependencies**: The script relies on external tools (`curl`, `jq`, `yq`). Ensure these tools are installed and properly configured.
