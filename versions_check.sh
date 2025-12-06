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

# Get recent releases for configurable versions
# Default to 4.19 and 4.20 for upgrade scenario
SOURCE_VERSION="${SOURCE_VERSION:-4.19}"
TARGET_VERSION="${TARGET_VERSION:-4.20}"

echo "Recent ${SOURCE_VERSION} releases:"
get_recent_releases "${SOURCE_VERSION}"
echo

echo "Recent ${TARGET_VERSION} releases:"
get_recent_releases "${TARGET_VERSION}"
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

# Get the latest releases for source and target versions
echo "Fetching the latest minor versions..."
echo "Source version: ${SOURCE_VERSION}, Target version: ${TARGET_VERSION}"
echo "Fetching the latest patch versions..."
latest_source=$(get_latest_patch "${SOURCE_VERSION}")
echo "Fetching latest ${TARGET_VERSION} release..."
latest_target=$(get_latest_patch "${TARGET_VERSION}")

if [[ -z "$latest_source" || -z "$latest_target" ]]; then
    echo "Failed to fetch latest releases. Please check your network connection."
    exit 1
fi

echo "Latest ${SOURCE_VERSION} release: $latest_source"
echo "Latest ${TARGET_VERSION} release: $latest_target"

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
display_release_info $latest_source
display_release_info $latest_target

# Check upgrade path
echo "Checking upgrade path from $latest_source to $latest_target"
upgrade_path=$(curl -s -H "Accept: application/json" "https://api.openshift.com/api/upgrades_info/v1/graph?channel=stable-${TARGET_VERSION}" | \
    jq --arg from "$latest_source" --arg to "$latest_target" \
    '.nodes[] | select(.version == $from or .version == $to) | {version: .version, release: .payload}')

if [[ -z "$upgrade_path" ]]; then
    echo "No direct upgrade path exists from $latest_source to $latest_target."
else
    echo "$upgrade_path"
fi


# This script updates the OpenShift version information in the extra_vars/download-to-tar-vars.yml file.
# Usage:
#   ./versions_check.sh [--auto-update | --skip-update]
#   SOURCE_VERSION=4.19 TARGET_VERSION=4.20 ./versions_check.sh --auto-update
#
# Options:
#   --auto-update   Automatically update the OpenShift versions without prompting.
#   --skip-update   Skip the version update check.
#
# Environment Variables:
#   SOURCE_VERSION  Source OCP version (default: 4.19)
#   TARGET_VERSION  Target OCP version (default: 4.20)
#
# The script uses the 'yq' command to modify the YAML file. If the USE_SUDO variable is set, it will use sudo to run the yq command.
update_vars_file() {
    # Update versions - minVersion = maxVersion for single version sync (avoids downloading entire range)
    ${USE_SUDO} yq eval -i "
        .openshift_releases[0].name = \"stable-${SOURCE_VERSION}\" |
        .openshift_releases[0].minVersion = \"$latest_source\" |
        .openshift_releases[0].maxVersion = \"$latest_source\" |
        .openshift_releases[1].name = \"stable-${TARGET_VERSION}\" |
        .openshift_releases[1].minVersion = \"$latest_target\" |
        .openshift_releases[1].maxVersion = \"$latest_target\"
    " extra_vars/download-to-tar-vars.yml
    
    # Also update operator catalog versions
    ${USE_SUDO} yq eval -i "
        .operators[0].catalog = \"registry.redhat.io/redhat/certified-operator-index:v${SOURCE_VERSION}\" |
        .operators[1].catalog = \"registry.redhat.io/redhat/redhat-operator-index:v${SOURCE_VERSION}\" |
        .operators[2].catalog = \"registry.redhat.io/redhat/certified-operator-index:v${TARGET_VERSION}\" |
        .operators[3].catalog = \"registry.redhat.io/redhat/redhat-operator-index:v${TARGET_VERSION}\"
    " extra_vars/download-to-tar-vars.yml
}

if [[ "$1" == "--auto-update" ]]; then
    update_vars_file
    echo "Versions automatically updated in extra_vars/download-to-tar-vars.yml"
    echo "  Source: ${SOURCE_VERSION} -> $latest_source"
    echo "  Target: ${TARGET_VERSION} -> $latest_target"
elif [[ "$1" != "--skip-update" ]]; then
    echo ""
    echo "This will set specific versions (not ranges) to avoid downloading too much data:"
    echo "  Source: ${SOURCE_VERSION} -> $latest_source (single version)"
    echo "  Target: ${TARGET_VERSION} -> $latest_target (single version)"
    echo ""
    read -p "Would you like to update the versions in extra_vars/download-to-tar-vars.yml? (y/n): " update_choice
    if [[ "$update_choice" == "y" ]]; then
        update_vars_file
        echo "Versions updated in extra_vars/download-to-tar-vars.yml"
    else
        echo "Skipping version update."
    fi
else
    echo "Skipping version update check."
fi
