terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
 region  = "us-east-1"

 default_tags {
   tags = {
     Project = "Spellbreak"
   }
 }
}

data "aws_ami" "spellbreak-balanced" {
  most_recent      = true
  owners           = ["self"]

  filter {
    name   = "name"
    values = ["community-server-balanced-*"]
  }
}

resource "aws_instance" "spellbreak-us-east-1" {
  ami           = data.aws_ami.spellbreak-balanced.id
  instance_type = "t2.xlarge"

  network_interface {
    network_interface_id = aws_network_interface.spellbreak-us-east-1a.id
    device_index         = 0
  }

  credit_specification {
    cpu_credits = "unlimited"
  }

  instance_market_options {
    market_type = "spot"

    spot_options {
      max_price = 0.18
      spot_instance_type = "persistent"
      instance_interruption_behavior = "stop"
    }
  }
}