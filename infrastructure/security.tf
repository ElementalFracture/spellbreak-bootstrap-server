resource "aws_security_group" "remote-desktop" {
  name        = "remote-desktop"
  description = "Allows inbound Remote Desktop traffic for admins"
  vpc_id      = aws_vpc.spellbreak.id

  lifecycle {
    ignore_changes = all
  }
}

resource "aws_security_group" "spellbreak-inbound" {
  name        = "spellbreak-inbound"
  description = "Allows inbound traffic from Spellbreak ports"
  vpc_id      = aws_vpc.spellbreak.id

  ingress {
    description      = "Spellbreak"
    from_port        = 7770
    to_port          = 9270
    protocol         = "udp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}