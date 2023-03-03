terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.54.0"
    }
  }
}


provider "aws" {
  region = "us-east-1"
}
####LOCAL VARIABLES FOR HOLDING VM CONFIGURATION
locals {
  server_configuration = [{
    application_name       = "web01-centos"
    ami                    = "ami-06cf02a98a61f9f5e"
    instance_type          = "t2.micro"
    key_name               = "centos-key"
    subnet_id              = ["aws_subnet.subnet_ot.id"]
    vpc_security_group_ids = ["aws_security_group.ot_sg.id"]
    },
    {
      application_name       = "web02-ubuntu"
      ami                    = "ami-0778521d914d23bc1"
      instance_type          = "t2.micro"
      key_name               = "ubuntu-key"
      subnet_id              = ["aws_subnet.subnet_ot.id"]
      vpc_security_group_ids = ["aws_security_group.ot_sg.id"]
    }
  ]
}



####LOCAL VARIABLES FOR SG RULES, INTENDED FOR DYNAMIC BLOCK
locals {
  ingress_rules = [{

    port        = 22
    protocol    = "tcp"
    description = "SSH"
    cidr_blocks = ["109.165.195.137/32"]
    },
    {
      port        = 0
      protocol    = "all"
      description = "Internet allow"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}


####VPC
resource "aws_vpc" "vpc_ot" {
  cidr_block = "10.0.0.0/18"

  tags = {
    Name = "vpc-ot"
  }
}
####SUBNETS
resource "aws_subnet" "subnet_ot" {

  vpc_id = aws_vpc.vpc_ot.id

  cidr_block = "10.0.0.0/19"

  availability_zone = "us-east-1c"

  tags = {
    Name = "subnet-ot"
  }
}

resource "aws_subnet" "subnet_ot_2" {

  vpc_id = aws_vpc.vpc_ot.id

  cidr_block = "10.0.32.0/19"

  availability_zone = "us-east-1d"
  tags = {
    Name = "subnet-ot-2"
  }
}

####DATA CODE BLOCK FOR RETRIEVING ID'S OF SUBNETS

data "aws_subnets" "subnetids" {
  filter {
    name   = "vpc-id"
    values = [aws_vpc.vpc_ot.id]
  }
}


####INTERNET GATEWAY
resource "aws_internet_gateway" "gateway_ot" {
  vpc_id = aws_vpc.vpc_ot.id

  tags = {
    Name = "gateway-ot"
  }
}
####DECLARING TEMPLATE FILE AND TEMPLATE VARIABLE WHICH HOLD USERDATA SCRIPT
data "template_file" "user_data" {
  template = file("userdata.tpl")
}

resource "aws_instance" "web" {
  for_each               = { for srv in local.server_configuration : srv.application_name => srv }
  ami                    = each.value.ami
  instance_type          = each.value.instance_type
  subnet_id              = aws_subnet.subnet_ot.id
  vpc_security_group_ids = [aws_security_group.ot_sg.id]
  key_name               = each.value.key_name
  tags = {
    Name = "${each.value.application_name}"
  }

  user_data = data.template_file.user_data.template
}

####ASSIGNING PUBLIC STATIC IP TO BOTH OF MACHINES
resource "aws_eip" "eip_ot" {
  for_each = { for idx, val in aws_instance.web : idx => val }
  instance = each.value.id
  vpc      = true

}

####CREATING SECURITY GROUP WITH DYNAMIC BLOCK
resource "aws_security_group" "ot_sg" {
  name        = "ot-sg"
  description = "Allow ssh from my Computer and open connection to internet"
  vpc_id      = aws_vpc.vpc_ot.id

  dynamic "ingress" {
    for_each = local.ingress_rules

    content {
      description = ingress.value.description
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }

  }

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    description     = "Allow connection from lb sg"
    security_groups = [aws_security_group.ot_alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


####CREATING SECURITY GROUP FOR LOAD BALANCER
resource "aws_security_group" "ot_alb_sg" {
  name        = "ot-alb-sg"
  description = "Allow inbound traffic to load balancer"
  vpc_id      = aws_vpc.vpc_ot.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "all"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

####ROUTE TABLE THAT ROUTES TRAFFIC FROM SUBNET WHERE MACHINES ARE LOCATED TO INTERNET GATEWAY
resource "aws_route_table" "ot_rt" {
  vpc_id = aws_vpc.vpc_ot.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gateway_ot.id
  }

}
####ASSOCIATE ROUTE TABLE WITH SUBNET OF MACHINES
resource "aws_route_table_association" "ot_associatie" {
  subnet_id      = aws_subnet.subnet_ot.id
  route_table_id = aws_route_table.ot_rt.id

}

####2 TARGET GROUPS
resource "aws_alb_target_group" "ot_tg_1" {
  name     = "ot-tg-1"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc_ot.id


  health_check {
    path                = "/crispy/index.html"
    port                = 80
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

resource "aws_alb_target_group" "ot_tg_2" {
  name     = "ot-tg-2"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc_ot.id

  health_check {
    path                = "/waso/index.html"
    port                = 80
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

####ATTACH INSTANCES WITH TARGET GROUP
resource "aws_alb_target_group_attachment" "ot_tg_attach_1" {
  for_each         = { for idx, val in aws_instance.web : idx => val if val.key_name == "centos-key" }
  target_group_arn = aws_alb_target_group.ot_tg_1.arn
  target_id        = each.value.id
  port             = 80
}

resource "aws_alb_target_group_attachment" "ot_tg_attach_2" {
  for_each         = { for idx, val in aws_instance.web : idx => val if val.key_name == "ubuntu-key" }
  target_group_arn = aws_alb_target_group.ot_tg_2.arn
  target_id        = each.value.id
  port             = 80
}

####LOAD BALANCER
resource "aws_alb" "ot_alb" {
  name            = "ot-alb"
  internal        = false
  security_groups = [aws_security_group.ot_alb_sg.id]
  subnets         = [aws_subnet.subnet_ot.id, aws_subnet.subnet_ot_2.id]



}
####LISTENER FOR LOAD BALANCER
resource "aws_alb_listener" "ot_listener_1" {
  load_balancer_arn = aws_alb.ot_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.ot_tg_1.arn
  }


}

####LISTENER RULES THAT ARE BASE ON PATH
resource "aws_alb_listener_rule" "ot_listener_rule_1" {
  listener_arn = aws_alb_listener.ot_listener_1.arn

  action {
    target_group_arn = aws_alb_target_group.ot_tg_1.arn
    type             = "forward"
  }

  condition {
    path_pattern {
      values = ["/crispy*"]
    }
  }
}

resource "aws_alb_listener_rule" "ot_listener_rule_2" {
  listener_arn = aws_alb_listener.ot_listener_1.arn

  action {
    target_group_arn = aws_alb_target_group.ot_tg_2.arn
    type             = "forward"
  }

  condition {
    path_pattern {
      values = ["/waso*"]
    }
  }
}
