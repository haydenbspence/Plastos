# syntax=docker/dockerfile:1.4
ARG ROOT_IMAGE=ubuntu:25.04

FROM --platform=$BUILDPLATFORM $ROOT_IMAGE AS base

LABEL org.opencontainers.image.title="Broadsea Foundation"
LABEL org.opencontainers.image.description="OHDSI Broadsea foundation image"
LABEL org.opencontainers.image.vendor="OHDSI"
LABEL org.opencontainers.image.licenses="Apache-2.0"

ARG MN_USER="ohdsi"
ARG MN_UID="1000"
ARG MN_GID="100"
ARG PYTHON_VERSION=3.12

# Install system packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        bzip2 \
        ca-certificates \
        curl \
        locales \
        netbase \
        sudo \
        tini \
        dos2unix \
        wget && \
    apt-get clean && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen

ENV GRANT_SUDO=yes \
    DEBIAN_FRONTEND=noninteractive \
    CONDA_DIR=/opt/conda \
    SHELL=/bin/bash \
    MN_USER="${MN_USER}" \
    MN_UID=${MN_UID} \
    MN_GID=${MN_GID} \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8 \
    LANGUAGE=C.UTF-8 

ENV PATH="${CONDA_DIR}/bin:${PATH}" \
    HOME="/home/${MN_USER}"  

# Copy and setup permissions script
COPY fix-permissions /usr/local/bin/fix-permissions
RUN chmod +x /usr/local/bin/fix-permissions && \
    dos2unix /usr/local/bin/fix-permissions

RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc && \
    echo 'eval "$(conda shell.bash hook)"' >> /etc/skel/.bashrc

# Remove existing user if it exists
RUN if getent passwd 1000 > /dev/null; then \
        userdel -r $(getent passwd 1000 | cut -d: -f1); \
    fi

# Create user and directories
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
    sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    useradd --no-log-init --create-home --shell /bin/bash --uid "${MN_UID}" --no-user-group "${MN_USER}" && \
    mkdir -p "${CONDA_DIR}" && \
    chown "${MN_USER}:${MN_GID}" "${CONDA_DIR}" && \
    chmod g+w /etc/passwd && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${MN_USER}"

USER ${MN_UID}

# Pin the Python version here, or set it to "default"
ARG PYTHON_VERSION=3.12

# Setup work directory for backward-compatibility
RUN mkdir "/home/${MN_USER}/work" && \
    fix-permissions "/home/${MN_USER}"

# Download and install Micromamba, and initialize the Conda prefix.
#   <https://github.com/mamba-org/mamba#micromamba>
#   Similar projects using Micromamba:
#     - Micromamba-Docker: <https://github.com/mamba-org/micromamba-docker>
#     - repo2docker: <https://github.com/jupyterhub/repo2docker>
# Install Python, Mamba, and jupyter_core
# Cleanup temporary files and remove Micromamba
# Correct permissions
# Do all this in a single RUN command to avoid duplicating all of the
# files across image layers when the permissions change
COPY --chown="${MN_UID}:${MN_GID}" initial-condarc "${CONDA_DIR}/.condarc"
WORKDIR /tmp
RUN set -x && \
    arch=$(uname -m) && \
    if [ "${arch}" = "x86_64" ]; then \
        # Should be simpler, see <https://github.com/mamba-org/mamba/issues/1437>
        arch="64"; \
    fi && \
    # https://mamba.readthedocs.io/en/latest/installation/micromamba-installation.html#linux-and-macos
    wget --progress=dot:giga -O - \
        "https://micro.mamba.pm/api/micromamba/linux-${arch}/latest" | tar -xvj bin/micromamba && \
    PYTHON_SPECIFIER="python=${PYTHON_VERSION}" && \
    if [[ "${PYTHON_VERSION}" == "default" ]]; then PYTHON_SPECIFIER="python"; fi && \
    # Install the packages
    ./bin/micromamba install \
        --root-prefix="${CONDA_DIR}" \
        --prefix="${CONDA_DIR}" \
        --yes \
        'jupyter_core' \
        # excluding mamba 2.X due to several breaking changes
        # https://github.com/jupyter/docker-stacks/pull/2147
        'mamba<2.0.0' \
        "${PYTHON_SPECIFIER}" && \
    rm -rf /tmp/bin/ && \
    # Pin major.minor version of python
    # https://conda.io/projects/conda/en/latest/user-guide/tasks/manage-pkgs.html#preventing-packages-from-updating-pinning
    mamba list --full-name 'python' | awk 'END{sub("[^.]*$", "*", $2); print $1 " " $2}' >> "${CONDA_DIR}/conda-meta/pinned" && \
    mamba clean --all -f -y && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${MN_USER}"


# Copy local files as late as possible to avoid cache busting
COPY run-hooks.sh start.sh /usr/local/bin/

# Configure container entrypoint
ENTRYPOINT ["tini", "-g", "--", "start.sh"]

USER root

# Create dirs for startup hooks
RUN mkdir /usr/local/bin/start-notebook.d && \
    mkdir /usr/local/bin/before-notebook.d

COPY 10activate-conda-env.sh /usr/local/bin/before-notebook.d/

# Switch back to jovyan to avoid accidental container runs as root
USER ${NB_UID}

WORKDIR "${HOME}"