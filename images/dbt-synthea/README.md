# Broadsea Foundation Image

The ohdsi/broadsea-foundation image is a versatile foundation image designed to support a wide range of options common across all core stacks. It serves as the basis for building Quarto-related applications.

## Key Features

### Core Components

- **Package Managers**: 
  - Conda: Cross-platform, language-agnostic binary package manager
  - Mamba: Reimplementation of conda in C++, used by default for package installations

- **User Configuration**:
  - Unprivileged user 'ohdsi' (uid=1000, configurable) in group 'users' (gid=100)
  - Ownership of /home/ohdsi and /opt/conda directories

- **Container Entry Point**:
  - tini and start.sh script for running alternative commands
  - run-hooks.sh script for sourcing/run files in a given directory

- **Security Options**:
  - Passwordless sudo support

- **Common Libraries**:
  - bzip2, ca-certificates, locales

- **Utility Tools**:
  - wget for downloading external files

- **Scientific Computing Packages**: None pre-installed

## Usage

This image provides a lightweight foundation for building various data science and analytics applications. It can be extended with additional packages and tools as needed.
