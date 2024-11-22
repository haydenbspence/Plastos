ARG BASE_IMAGE=broadsea-foundation
FROM $BASE_IMAGE

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root

RUN apt-get update --yes

USER ${MN_UID}
WORKDIR /tmp

COPY environment.yml /usr/local/bin/environment.yml
COPY ./requirements/duckdb.txt /tmp/duckdb.txt

RUN mamba install -f /usr/local/bin/environment.yml