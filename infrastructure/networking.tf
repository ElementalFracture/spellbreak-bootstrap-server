resource "aws_vpc" "spellbreak" {
    cidr_block = "172.16.0.0/16"
    enable_dns_hostnames = true
    enable_dns_support   = true
    
    tags = {
        Name = "spellbreak"
    }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.spellbreak.id

  tags = {
    Name = "spellbreak-main"
  }
}

resource "aws_subnet" "spellbreak-us-east1a" {
  vpc_id            = aws_vpc.spellbreak.id
  cidr_block        = "172.16.10.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_route_table" "spellbreak" {
 vpc_id = aws_vpc.spellbreak.id
 
 route {
   cidr_block = "0.0.0.0/0"
   gateway_id = aws_internet_gateway.gw.id
 }
 
 tags = {
   Name = "Spellbreak Route Table"
 }
}

resource "aws_route_table_association" "public_subnet_asso" {
 subnet_id      = aws_subnet.spellbreak-us-east1a.id
 route_table_id = aws_route_table.spellbreak.id
}

resource "aws_network_interface" "spellbreak-us-east-1a" {
  subnet_id   = aws_subnet.spellbreak-us-east1a.id
  private_ips = ["172.16.10.100"]
  
  security_groups      = [
    aws_security_group.spellbreak-inbound.id,
    aws_security_group.remote-desktop.id
  ]
}

resource "aws_eip" "us-east-1a" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.spellbreak-us-east-1a.id
  associate_with_private_ip = "172.16.10.100"
}