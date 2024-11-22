#!/bin/bash

# Enable strict error handling:
# -e: exit on error
# -u: error on undefined variables
# -o pipefail: return value of pipeline is value of last (rightmost) command to exit with non-zero status
set -euo pipefail

# Set Internal Field Separator to newline and tab for safer iteration
IFS=$'\n\t'

# Define exit status codes as readonly constants
readonly EXIT_SUCCESS=0
readonly EXIT_INVALID_ARGS=1
readonly EXIT_INVALID_DIR=2
readonly EXIT_HOOK_FAILURE=3

# Display usage instructions when script is called incorrectly
usage() {
    echo "Usage: $0 <hooks-directory>"
    echo "Executes *.sh scripts and executables from the specified directory"
}

# Logging function that prepends timestamp to messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Execute a single hook file
# Args:
#   $1: Path to the hook file
# Returns:
#   0 on success, 1 on failure
run_hook() {
    local hook_path="$1"
    local hook_name
    hook_name=$(basename "$hook_path")
    
    # Check if file exists and is readable
    if [[ -f "$hook_path" && -r "$hook_path" ]]; then
        if [[ "$hook_path" == *.sh ]]; then
            # Source .sh files to execute them in current shell context
            log "Sourcing shell script: $hook_name"
            # Disable shellcheck warning about sourcing dynamic file
            # shellcheck disable=SC1090
            if ! source "$hook_path"; then
                log "ERROR: Failed to source $hook_name"
                return 1
            fi
        elif [[ -x "$hook_path" ]]; then
            # Execute files with executable permission
            log "Running executable: $hook_name"
            if ! "$hook_path"; then
                log "ERROR: Failed to execute $hook_name"
                return 1
            fi
        else
            log "Skipping non-executable: $hook_name"
        fi
    fi
    return 0
}

# Main script execution
main() {
    # Validate command line arguments
    if [[ $# -ne 1 ]]; then
        usage
        return $EXIT_INVALID_ARGS
    fi

    local hooks_dir="$1"
    # Verify hooks directory exists
    if [[ ! -d "$hooks_dir" ]]; then
        log "ERROR: Directory $hooks_dir doesn't exist or is not a directory"
        return $EXIT_INVALID_DIR
    fi

    log "Running hooks in: $hooks_dir as uid: $(id -u) gid: $(id -g)"

    # Track number of failed hooks
    local failed_hooks=0
    
    # Use find to get all files in directory, pipe to while loop
    # -print0 and -d '' handle filenames with spaces
    while IFS= read -r -d '' hook; do
        if ! run_hook "$hook"; then
            ((failed_hooks++))
        fi
    done < <(find "$hooks_dir" -maxdepth 1 -type f -print0)

    log "Completed running hooks in: $hooks_dir"
    if ((failed_hooks > 0)); then
        log "WARNING: $failed_hooks hooks failed execution"
        return $EXIT_HOOK_FAILURE
    fi
    return $EXIT_SUCCESS
}

# Execute main function with all script arguments
main "$@"