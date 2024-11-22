#!/bin/bas

# Copyright (c) 2024 Observational Health Data Sciences and Informatics.
# Distributed under the Apache 2.0 License.
#
# Configures conda shell integration and environment activation
#
# This script sets up the conda shell hooks to enable proper conda initialization
# and automatic activation of the base environment. The hooks allow conda to modify
# the shell environment and automatically manage virtual environments.
#
# Documentation: https://docs.conda.io/projects/conda/en/latest/dev-guide/deep-dives/activation.html

eval "$(conda shell.bash hook)"