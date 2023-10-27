packer {
  required_plugins {
    amazon = {
      version = ">= 0.0.1"
      source = "github.com/hashicorp/amazon"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

locals { timestamp = regex_replace(timestamp(), "[- TZ:]", "") }

# source blocks are generated from your builders; a source can be referenced in
# build blocks. A build block runs provisioner and post-processors on a
# source.
source "amazon-ebs" "community-server-base" {
  ami_name      = "community-server-balanced-${local.timestamp}"
  communicator  = "winrm"
  instance_type = "t2.medium"
  region        = "${var.region}"
  source_ami_filter {
    filters = {
      name                = "community-server-base-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["self"]
  }
  winrm_password = "SuperSpellBS3cr3t!!!!"
  winrm_username = "Administrator"
}

# a build block invokes sources and runs provisioning steps on them.
build {
  name    = "spellbreak"
  sources = ["source.amazon-ebs.community-server-base"]
  
  provisioner "file" {
    source = "${path.root}/Elefrac balance patch 3-2-3-1694989427.zip"
    destination = "C:\\spellbreak-base-files\\balance-patch.zip"
  }

  provisioner "powershell" {
    environment_vars = []
    script           = "${path.root}/build/provision_server.ps1"
  }
}


