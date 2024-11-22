#!/bin/bash
# Copyright (c) 2024 Observational Health Data Sciences and Informatics.
# Distributed under the Apache 2.0 License.

set -e

# Log messages only if they're errors/warnings or verbose logging is enabled
_log () {
    if [[ "$*" == "ERROR:"* ]] || [[ "$*" == "WARNING:"* ]] || [[ "${JUPYTER_DOCKER_STACKS_QUIET}" == "" ]]; then
        echo "$@"
    fi
}

# Remove specified environment variables
unset_explicit_env_vars () {
    if [ -n "${JUPYTER_ENV_VARS_TO_UNSET}" ]; then
        for env_var_to_unset in $(echo "${JUPYTER_ENV_VARS_TO_UNSET}" | tr ',' ' '); do
            _log "Unset ${env_var_to_unset} due to JUPYTER_ENV_VARS_TO_UNSET"
            unset "${env_var_to_unset}"
        done
        unset JUPYTER_ENV_VARS_TO_UNSET
    fi
}

# Use bash shell if no command provided
if [ $# -eq 0 ]; then
    cmd=( "bash" )
else
    cmd=( "$@" )
fi

# Prevent duplicate execution via ENTRYPOINT and CMD
if [ "${_START_SH_EXECUTED}" = "1" ]; then
    _log "WARNING: start.sh is the default ENTRYPOINT, do not include it in CMD"
    _log "Executing the command:" "${cmd[@]}"
    exec "${cmd[@]}"
else
    export _START_SH_EXECUTED=1
fi

# Execute startup hooks with current user permissions
source /usr/local/bin/run-hooks.sh /usr/local/bin/start-notebook.d

# ROOT USER SECTION
# Handles user setup, permissions, and sudo configuration
if [ "$(id -u)" == 0 ]; then
    # Configure user account:
    # NB_USER: Username
    # NB_UID: User ID
    # NB_GID: Group ID
    # NB_GROUP: Group name
    # GRANT_SUDO: Enable sudo access
    # CHOWN_HOME: Set home directory ownership
    # CHOWN_EXTRA: Additional paths to change ownership
    
    # Update jovyan user to match NB_USER settings
    if id jovyan &> /dev/null; then
        if ! usermod --home "/home/${NB_USER}" --login "${NB_USER}" jovyan 2>&1 | grep "no changes" > /dev/null; then
            _log "Updated the jovyan user:"
            _log "- username: jovyan       -> ${NB_USER}"
            _log "- home dir: /home/jovyan -> /home/${NB_USER}"
        fi
    elif ! id -u "${NB_USER}" &> /dev/null; then
        _log "ERROR: Neither the jovyan user nor '${NB_USER}' exists. This could be the result of stopping and starting, the container with a different NB_USER environment variable."
        exit 1
    fi

    # Update UID/GID if needed
    if [ "${NB_UID}" != "$(id -u "${NB_USER}")" ] || [ "${NB_GID}" != "$(id -g "${NB_USER}")" ]; then
        _log "Update ${NB_USER}'s UID:GID to ${NB_UID}:${NB_GID}"
        # Create/update group
        if [ "${NB_GID}" != "$(id -g "${NB_USER}")" ]; then
            groupadd --force --gid "${NB_GID}" --non-unique "${NB_GROUP:-${NB_USER}}"
        fi
        # Recreate user with new settings
        userdel "${NB_USER}"
        useradd --no-log-init --home "/home/${NB_USER}" --shell /bin/bash --uid "${NB_UID}" --gid "${NB_GID}" --groups 100 "${NB_USER}"
    fi

    # Special handling for root user
    if [ "${NB_USER}" = "root" ] && [ "${NB_UID}" = "$(id -u "${NB_USER}")" ] && [ "${NB_GID}" = "$(id -g "${NB_USER}")" ]; then
        sed -i "s|/root|/home/root|g" /etc/passwd
        CP_OPTS="-a --no-preserve=ownership"
    fi

    # Handle home directory migration/linking
    if [[ "${NB_USER}" != "jovyan" ]]; then
        if [[ ! -e "/home/${NB_USER}" ]]; then
            _log "Attempting to copy /home/jovyan to /home/${NB_USER}..."
            mkdir "/home/${NB_USER}"
            if cp ${CP_OPTS:--a} /home/jovyan/. "/home/${NB_USER}/"; then
                _log "Success!"
            else
                _log "Failed to copy data from /home/jovyan to /home/${NB_USER}!"
                _log "Attempting to symlink /home/jovyan to /home/${NB_USER}..."
                if ln -s /home/jovyan "/home/${NB_USER}"; then
                    _log "Success creating symlink!"
                else
                    _log "ERROR: Failed copy data from /home/jovyan to /home/${NB_USER} or to create symlink!"
                    exit 1
                fi
            fi
        fi
        # Update working directory path if needed
        if [[ "${PWD}/" == "/home/jovyan/"* ]]; then
            new_wd="/home/${NB_USER}/${PWD:13}"
            _log "Changing working directory to ${new_wd}"
            cd "${new_wd}"
        fi
    fi

    # Set directory ownership
    if [[ "${CHOWN_HOME}" == "1" || "${CHOWN_HOME}" == "yes" ]]; then
        _log "Ensuring /home/${NB_USER} is owned by ${NB_UID}:${NB_GID} ${CHOWN_HOME_OPTS:+(chown options: ${CHOWN_HOME_OPTS})}"
        chown ${CHOWN_HOME_OPTS} "${NB_UID}:${NB_GID}" "/home/${NB_USER}"
    fi
    if [ -n "${CHOWN_EXTRA}" ]; then
        for extra_dir in $(echo "${CHOWN_EXTRA}" | tr ',' ' '); do
            _log "Ensuring ${extra_dir} is owned by ${NB_UID}:${NB_GID} ${CHOWN_EXTRA_OPTS:+(chown options: ${CHOWN_EXTRA_OPTS})}"
            chown ${CHOWN_EXTRA_OPTS} "${NB_UID}:${NB_GID}" "${extra_dir}"
        done
    fi

    # Add conda to sudo path
    sed -r "s#Defaults\s+secure_path\s*=\s*\"?([^\"]+)\"?#Defaults secure_path=\"${CONDA_DIR}/bin:\1\"#" /etc/sudoers | grep secure_path > /etc/sudoers.d/path

    # Configure sudo access
    if [[ "${GRANT_SUDO}" == "1" || "${GRANT_SUDO}" == "yes" ]]; then
        _log "Granting ${NB_USER} passwordless sudo rights!"
        echo "${NB_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/added-by-start-script
    fi

    # Run pre-notebook hooks as root
    source /usr/local/bin/run-hooks.sh /usr/local/bin/before-notebook.d
    unset_explicit_env_vars

    # Execute command as specified user
    _log "Running as ${NB_USER}:" "${cmd[@]}"
    if [ "${NB_USER}" = "root" ] && [ "${NB_UID}" = "$(id -u "${NB_USER}")" ] && [ "${NB_GID}" = "$(id -g "${NB_USER}")" ]; then
        HOME="/home/root" exec "${cmd[@]}"
    else
        # Preserve environment when switching users
        exec sudo --preserve-env --set-home --user "${NB_USER}" \
            LD_LIBRARY_PATH="${LD_LIBRARY_PATH}" \
            PATH="${PATH}" \
            PYTHONPATH="${PYTHONPATH:-}" \
            "${cmd[@]}"
    fi

# NON-ROOT USER SECTION
# Handle limitations when container starts as non-root
else
    # Check for sudo configuration attempt
    if [[ "${GRANT_SUDO}" == "1" || "${GRANT_SUDO}" == "yes" ]]; then
        _log "WARNING: container must be started as root to grant sudo permissions!"
    fi

    # Store default jovyan user IDs
    JOVYAN_UID="$(id -u jovyan 2>/dev/null)"
    JOVYAN_GID="$(id -g jovyan 2>/dev/null)"

    # Ensure current user has passwd entry
    if ! whoami &> /dev/null; then
        _log "There is no entry in /etc/passwd for our UID=$(id -u). Attempting to fix..."
        if [[ -w /etc/passwd ]]; then
            _log "Renaming old jovyan user to nayvoj ($(id -u jovyan):$(id -g jovyan))"

            # Create temporary passwd file due to /etc write restrictions
            sed --expression="s/^jovyan:/nayvoj:/" /etc/passwd > /tmp/passwd
            echo "${NB_USER}:x:$(id -u):$(id -g):,,,:/home/jovyan:/bin/bash" >> /tmp/passwd
            cat /tmp/passwd > /etc/passwd
            rm /tmp/passwd

            _log "Added new ${NB_USER} user ($(id -u):$(id -g)). Fixed UID!"

            if [[ "${NB_USER}" != "jovyan" ]]; then
                _log "WARNING: user is ${NB_USER} but home is /home/jovyan. You must run as root to rename the home directory!"
            fi
        else
            _log "WARNING: unable to fix missing /etc/passwd entry because we don't have write permission. Try setting gid=0 with \"--user=$(id -u):0\"."
        fi
    fi

    # Warn about user/group misconfigurations
    if [[ "${NB_USER}" != "jovyan" && "${NB_USER}" != "$(id -un)" ]]; then
        _log "WARNING: container must be started as root to change the desired user's name with NB_USER=\"${NB_USER}\"!"
    fi
    if [[ "${NB_UID}" != "${JOVYAN_UID}" && "${NB_UID}" != "$(id -u)" ]]; then
        _log "WARNING: container must be started as root to change the desired user's id with NB_UID=\"${NB_UID}\"!"
    fi
    if [[ "${NB_GID}" != "${JOVYAN_GID}" && "${NB_GID}" != "$(id -g)" ]]; then
        _log "WARNING: container must be started as root to change the desired user's group id with NB_GID=\"${NB_GID}\"!"
    fi

    # Check home directory permissions
    if [[ ! -w /home/jovyan ]]; then
        _log "WARNING: no write access to /home/jovyan. Try starting the container with group 'users' (100), e.g. using \"--group-add=users\"."
    fi

    # Run pre-notebook hooks
    source /usr/local/bin/run-hooks.sh /usr/local/bin/before-notebook.d
    unset_explicit_env_vars

    # Execute command
    _log "Executing the command:" "${cmd[@]}"
    exec "${cmd[@]}"
fi