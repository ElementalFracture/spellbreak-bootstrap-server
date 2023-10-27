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
  ami_name      = "community-server-base-${local.timestamp}"
  communicator  = "winrm"
  instance_type = "t2.medium"
  region        = "${var.region}"
  source_ami_filter {
    filters = {
      name                = "Windows_Server-2016-English-Full-Base-2023.07.12"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["amazon"]
  }
  user_data_file = "${path.root}/build/setup_winrm.txt"
  winrm_password = "SuperSpellBS3cr3t!!!!"
  winrm_username = "Administrator"
}

# a build block invokes sources and runs provisioning steps on them.
build {
  name    = "spellbreak"
  sources = ["source.amazon-ebs.community-server-base"]

  provisioner "file" {
    source = "${path.root}/run/startup.cmd"
    destination = "%AppData%\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\startup.cmd"
  }
  
  provisioner "file" {
    source = "${path.root}/run/startup.ps1"
    destination = "C:\\spellbreak-base-files\\startup.ps1"
  }

  provisioner "powershell" {
    environment_vars = []
    script           = "${path.root}/build/provision_server.ps1"
  }
}


