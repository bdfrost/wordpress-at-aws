provider "aws" {
  region = "${var.aws_region}"
}

terraform {
  required_version = ">= 0.11"
}

resource "aws_vpc" "vpc" {
  cidr_block           = "${cidrsubnet(var.cidr_block, 0, 0)}"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags {
    Name        = "${var.environment}-vpc"
    Environment = "${var.environment}"
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags {
    Name        = "${var.environment}-internet-gateway"
    Environment = "${var.environment}"
  }
}

resource "aws_route_table" "public_routetable" {
  vpc_id = "${aws_vpc.vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.internet_gateway.id}"
  }

  tags {
    Name        = "${var.environment}-public-routetable"
    Environment = "${var.environment}"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = "${aws_vpc.vpc.id}"
  cidr_block              = "${cidrsubnet(var.cidr_block, 8, count.index)}"
  availability_zone       = "${element(var.availability_zones[var.aws_region], count.index)}"
  map_public_ip_on_launch = "${var.public_subnet_map_public_ip_on_launch}"
  count                   = "${length(var.availability_zones[var.aws_region])}"

  tags {
    Name        = "${var.environment}-${element(var.availability_zones[var.aws_region], count.index)}-public"
    Environment = "${var.environment}"
  }
}

resource "aws_route_table_association" "public_routing_table" {
  subnet_id      = "${element(aws_subnet.public_subnet.*.id, count.index)}"
  route_table_id = "${aws_route_table.public_routetable.id}"
  count          = "${length(var.availability_zones[var.aws_region])}"
}

resource "aws_route_table" "private_routetable" {
  count  = "${var.create_private_subnets ? 1 : 0}"
  vpc_id = "${aws_vpc.vpc.id}"

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = "${aws_nat_gateway.nat.id}"
  }

  tags {
    Name        = "${var.environment}-private-routetable"
    Environment = "${var.environment}"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id                  = "${aws_vpc.vpc.id}"
  cidr_block              = "${cidrsubnet(var.cidr_block, 8, length(var.availability_zones[var.aws_region]) + count.index)}"
  availability_zone       = "${element(var.availability_zones[var.aws_region], count.index)}"
  map_public_ip_on_launch = false
  count                   = "${var.create_private_subnets ? length(var.availability_zones[var.aws_region]) : 0}"

  tags {
    Name        = "${var.environment}-${element(var.availability_zones[var.aws_region], count.index)}-private"
    Environment = "${var.environment}"
  }
}

resource "aws_route_table_association" "private_routing_table" {
  subnet_id      = "${element(aws_subnet.private_subnet.*.id, count.index)}"
  route_table_id = "${aws_route_table.private_routetable.id}"
  count          = "${var.create_private_subnets ? length(var.availability_zones[var.aws_region]) : 0}"
}

resource "aws_eip" "nat" {
  vpc = true
}

resource "aws_nat_gateway" "nat" {
  count         = "${var.create_private_subnets ? 1 : 0}"
  allocation_id = "${aws_eip.nat.id}"
  subnet_id     = "${aws_subnet.public_subnet.0.id}"
}

resource "aws_route53_zone" "local" {
  count   = "${var.create_private_hosted_zone ? 1 : 0}"
  name    = "${var.environment}.local"
  comment = "${var.environment} - route53 - local hosted zone"

  tags {
    Name        = "${var.environment}-route53-private-hosted-zone"
    Environment = "${var.environment}"
  }

  vpc_id = "${aws_vpc.vpc.id}"
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "db_subnet_group"
#  subnet_ids = ["${aws_subnet.private_subnet.id}", "${aws_subnet.public_subnet.id}"]
  subnet_ids = ["${aws_subnet.private_subnet.*.id}"]
  tags {
    Name = "My DB subnet group"
  }
}

####################
#RDS
####################
resource "aws_db_instance" "default" {
  depends_on             = ["aws_security_group.default"]
  identifier             = "${var.identifier}"
  allocated_storage      = "${var.storage}"
  engine                 = "${var.engine}"
  engine_version         = "${lookup(var.engine_version, var.engine)}"
  instance_class         = "${var.instance_class}"
  name                   = "${var.db_name}"
  username               = "${var.TF_VAR_rds_username}"
  password               = "${var.TF_VAR_rds_password}"
  vpc_security_group_ids = ["${aws_security_group.default.id}"]
  db_subnet_group_name   = "${aws_db_subnet_group.db_subnet_group.id}"
}

####################
#Security Group
####################
resource "aws_security_group" "default" {
  name        = "main_rds_sg"
  description = "Allow all inbound traffic"
#  vpc_id      = "${var.vpc_id}"
  vpc_id      = "${aws_vpc.vpc.id}"

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "TCP"
    cidr_blocks = ["${var.cidr_blocks}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "${var.sg_name}"
  }
}
