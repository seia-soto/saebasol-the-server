# Saebasol The Server

Automated server configuration script of Heliotrope.

## Table of Contents

- [Usage](#usage)

----

# Usage

After preparing a bare metal server, clone this repository and edit `config.sh`, then execute `setup/initial-setup.sh`.

```
initial-setup.sh
Scripts to setup Heliotrope in one line.

Usage:
  sh ./setup/initial-setup.sh

  <subuser>     Subuser to run docker containers and services
  -h, --help    Display this mKessage
Example:
  ./setup/initial-setup.sh saebasol user@domain.tld
  ./setup/initial-setup.sh -h
  ./setup/initial-setup.sh --help
```
