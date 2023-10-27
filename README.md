# Spellbreak: Bootstrap Community Server

Provisions a AMI that can be spun up to run a cloud-hosted Spellbreak Community Server.

Created utilizing [Hashicorp Packer](https://www.packer.io/), with this tutorial as a base:
https://developer.hashicorp.com/packer/tutorials/cloud-production/aws-windows-image

## Installation

- [Hashicorp Packer](https://developer.hashicorp.com/packer/tutorials/docker-get-started/get-started-install-cli)

## Useful commands

```
# Builds unmodded base Spellbreak server
packer init base_server
packer build base_server

# Branches off of base server image with a balance mod
packer init balanced_server
packer build balanced_server
```