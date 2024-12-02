
FROM mambaorg/micromamba:2.0.4

COPY --chown=$MAMBA_USER:$MAMBA_USER env.yaml /tmp/env.yaml
RUN micromamba install --yes --file /tmp/env.yaml && \
    micromamba clean --all --yes
ARG MAMBA_DOCKERFILE_ACTIVATE=1  # (otherwise python will not be found)

COPY --chown=$MAMBA_USER:$MAMBA_USER .dbt /home/mambauser/.dbt

RUN git clone https://github.com/OHDSI/dbt-synthea.git /home/mambauser/dbt-synthea && \
    cd /home/mambauser/dbt-synthea && \
    pip3 install -r /home/mambauser/dbt-synthea/requirements/duckdb.txt && \
    pre-commit install && \
    dbt debug && \
    dbt deps && \
    dbt seed && \
    dbt seed --select states omop && \
    dbt build

ENTRYPOINT ["/usr/local/bin/_entrypoint.sh", "python"]

