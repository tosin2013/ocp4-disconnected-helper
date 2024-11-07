#!/bin/bash


# This script checks if the current user has root privileges.
# If the user is not root (EUID is not 0), it sets the USE_SUDO variable to "sudo".
# This allows subsequent commands to be run with sudo if necessary.
if [ "$EUID" -ne 0 ]
then
  export USE_SUDO="sudo"
fi

# Function to get recent releases for a given minor version
# This function retrieves the most recent releases for a specified OpenShift version.
#
# Arguments:
#   version: The major.minor version of OpenShift (e.g., "4.7").
#
# The function performs the following steps:
# 1. Constructs the channel name using the provided version (e.g., "stable-4.7").
# 2. Makes a GET request to the OpenShift upgrades information API to fetch the release graph for the specified channel.
# 3. Checks if the curl command was successful. If not, it prints an error message and returns 1.
# 4. Filters the JSON response to extract the versions that start with the specified version.
# 5. Sorts the versions in descending order and selects the top 10 most recent versions.
# 6. Prints the selected versions.
get_recent_releases() {
    local version=$1
    local channel="stable-${version}"
    local result

    result=$(curl -s -H "Accept: application/json" "https://api.openshift.com/api/upgrades_info/v1/graph?channel=${channel}")

    if [[ $? -ne 0 ]]; then
        echo "Error fetching release info for version ${version}"
        return 1
    fi

    echo "$result" | jq -r ".nodes | map(select(.version | startswith(\"${version}\"))) | sort_by(.version) | reverse | .[0:10] | .[].version"
}

# Get recent 4.15 and 4.16 releases
# This script prints the recent releases for specified OpenShift versions.
# It uses the function `get_recent_releases` to fetch and display the recent releases.
# The script currently checks for recent releases of versions 4.15 and 4.16.
echo "Recent 4.15 releases:"
get_recent_releases "4.15"
echo

echo "Recent 4.16 releases:"
get_recent_releases "4.16"
echo

# Function to get the latest patch version for a given minor version
# This function retrieves the latest patch version for a given OpenShift version.
# Arguments:
#   version: The major.minor version of OpenShift (e.g., 4.7).
# Returns:
#   The latest patch version available in the stable channel for the specified version.
# Usage:
#   latest_patch=$(get_latest_patch "4.7")
get_latest_patch() {
    local version=$1
    local channel="stable-${version}"

    curl -s -H "Accept: application/json" "https://api.openshift.com/api/upgrades_info/v1/graph?channel=${channel}" | \
    jq -r ".nodes[] | select(.version | startswith(\"${version}\")) | .version" | sort -V | tail -1
}

# Get the latest 4.15 and 4.16 releases
# This script fetches the latest patch versions for OpenShift 4.15 and 4.16 releases.
# It uses a function `get_latest_patch` to retrieve the latest patch version for the specified release.
# If the script fails to fetch the latest releases, it will output an error message and exit with status code 1.
echo "Fetching the two latest minor versions..."
echo "Latest minor versions: 4.15, 4.16"
echo "Fetching the latest patch versions for 4.15 and 4.16..."
latest_4_15=$(get_latest_patch "4.15")
echo "Fetching latest 4.16 release..."
latest_4_16=$(get_latest_patch "4.16")

if [[ -z "$latest_4_15" || -z "$latest_4_16" ]]; then
    echo "Failed to fetch latest releases. Please check your network connection."
    exit 1
fi

# This script prints the latest releases for versions 4.15 and 4.16.
# It uses the variables `latest_4_15` and `latest_4_16` to display the respective release versions.
echo "Latest 4.15 release: $latest_4_15"
echo "Latest 4.16 release: $latest_4_16"

# Function to display release info
# This script defines a function `display_release_info` that fetches and displays release information for a specified OpenShift version.
#
# Usage:
#   display_release_info <version>
#
# Arguments:
#   version: The OpenShift version for which to fetch release information.
#
# The function performs the following steps:
# 1. Extracts the major and minor version from the provided version to determine the appropriate channel (e.g., "stable-4.6").
# 2. Uses `curl` to send a GET request to the OpenShift upgrades information API for the specified channel.
# 3. Pipes the JSON response to `jq` to filter and format the release information for the specified version.
# 4. If the `jq` command fails (e.g., if the version is not found), it prints an error message.
#
# Dependencies:
# - `curl`: Command-line tool for transferring data with URLs.
# - `jq`: Command-line JSON processor.
display_release_info() {
    local version=$1
    local channel="stable-${version:0:4}"
    echo "Release information for $version:"
    curl -s -H "Accept: application/json" "https://api.openshift.com/api/upgrades_info/v1/graph?channel=${channel}" | \
        jq --arg version "$version" '.nodes[] | select(.version == $version) | {version: .version, releaseCreation: .metadata.io.openshift.upgrades.graph.release.created, displayVersion: .metadata.io.openshift.upgrades.graph.release.channels}' || \
        echo "Failed to fetch release info for $version"
    echo
}

# Display information for both latest releases
# This script displays release information for the specified versions.
# It calls the `display_release_info` function with the latest versions
# of 4.15 and 4.16 releases as arguments.
display_release_info $latest_4_15
display_release_info $latest_4_16

# Check upgrade path
# This script checks the upgrade path between two OpenShift versions.
# It fetches the upgrade graph from the OpenShift API for the stable-4.16 channel.
# The script uses the `curl` command to make an HTTP GET request to the API.
# The response is filtered using `jq` to select nodes matching the specified versions.
# The versions to check are provided by the variables $latest_4_15 and $latest_4_16.
# If the API request fails, an error message "Failed to fetch upgrade path information" is displayed.
echo "Checking upgrade path from $latest_4_15 to $latest_4_16"
upgrade_path=$(curl -s -H "Accept: application/json" "https://api.openshift.com/api/upgrades_info/v1/graph?channel=stable-4.16" | \
    jq --arg from "$latest_4_15" --arg to "$latest_4_16" \
    '.nodes[] | select(.version == $from or .version == $to) | {version: .version, release: .payload}')

if [[ -z "$upgrade_path" ]]; then
    echo "No direct upgrade path exists from $latest_4_15 to $latest_4_16."
else
    echo "$upgrade_path"
fi

# Prompt user to update versions or skip the update check
if [[ "$1" != "--skip-update" ]]; then
    read -p "Would you like to update the versions in extra_vars/download-to-tar-vars.yml? (y/n): " update_choice
    if [[ "$update_choice" == "y" ]]; then
        ${USE_SUDO} yq eval -i ".openshift_releases[0].minVersion = \"$latest_4_15\" | .openshift_releases[0].maxVersion = \"$latest_4_15\" |
.openshift_releases[1].minVersion = \"$latest_4_16\" | .openshift_releases[1].maxVersion = \"$latest_4_16\"" extra_vars/download-to-tar-vars.yml
        echo "Versions updated in extra_vars/download-to-tar-vars.yml"
    else
        echo "Skipping version update."
    fi
else
    echo "Skipping version update check."
fi
