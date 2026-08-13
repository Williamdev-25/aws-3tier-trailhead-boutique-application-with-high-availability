resource "aws_vpc" "main" {
  cidr_block = var.cidr_block

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name}-vpc"
  }
}


# =============== availability zones ===============
data "aws_availability_zones" "azs" {
  state = "available"
}


# =============== public subnets ===============
resource "aws_subnet" "public_subnet_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.cidr_block, 8, 0)
  availability_zone = data.aws_availability_zones.azs.names[0]

  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-public-subnet-1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.cidr_block, 8, 1)
  availability_zone = data.aws_availability_zones.azs.names[1]

  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-public-subnet-2"
  }
}


# =============== private subnets - application layer ===============
resource "aws_subnet" "private_app_subnet_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.cidr_block, 8, 2)
  availability_zone = data.aws_availability_zones.azs.names[0]

  tags = {
    Name = "${var.name}-private-app-subnet-1"
  }
}

resource "aws_subnet" "private_app_subnet_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.cidr_block, 8, 3)
  availability_zone = data.aws_availability_zones.azs.names[1]

  tags = {
    Name = "${var.name}-private-app-subnet-2"
  }
}


# =============== private subnets - database layer ===============
resource "aws_subnet" "private_db_subnet_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.cidr_block, 8, 4)
  availability_zone = data.aws_availability_zones.azs.names[0]

  tags = {
    Name = "${var.name}-private-db-subnet-1"
  }
}

resource "aws_subnet" "private_db_subnet_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.cidr_block, 8, 5)
  availability_zone = data.aws_availability_zones.azs.names[1]

  tags = {
    Name = "${var.name}-private-db-subnet-2"
  }
}


# =============== DB subnet group for RDS instance ===============
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "${var.environment}-db-subnet-group"
  subnet_ids = [aws_subnet.private_db_subnet_1.id, aws_subnet.private_db_subnet_2.id]

  tags = {
    Name = "${var.environment}-db-subnet-group"
  }
}


# =============== internet gateway ===============
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name}-igw"
  }
}


# =============== NAT gateways (one per AZ, for app tier outbound access) ===============
resource "aws_eip" "nat_eip_1" {
  domain = "vpc"

  tags = {
    Name = "${var.name}-nat-eip-1"
  }
}

resource "aws_eip" "nat_eip_2" {
  domain = "vpc"

  tags = {
    Name = "${var.name}-nat-eip-2"
  }
}

resource "aws_nat_gateway" "nat_gw_1" {
  allocation_id = aws_eip.nat_eip_1.id
  subnet_id     = aws_subnet.public_subnet_1.id

  tags = {
    Name = "${var.name}-nat-gw-1"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat_gw_2" {
  allocation_id = aws_eip.nat_eip_2.id
  subnet_id     = aws_subnet.public_subnet_2.id

  tags = {
    Name = "${var.name}-nat-gw-2"
  }

  depends_on = [aws_internet_gateway.igw]
}


# =============== public route table ===============
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.name}-public-rt"
  }
}

resource "aws_route_table_association" "public_subnet_1_assoc" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_subnet_2_assoc" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}


# =============== private route tables - app tier (route out via NAT) ===============
resource "aws_route_table" "private_app_rt_1" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw_1.id
  }

  tags = {
    Name = "${var.name}-private-app-rt-1"
  }
}

resource "aws_route_table" "private_app_rt_2" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw_2.id
  }

  tags = {
    Name = "${var.name}-private-app-rt-2"
  }
}

resource "aws_route_table_association" "private_app_subnet_1_assoc" {
  subnet_id      = aws_subnet.private_app_subnet_1.id
  route_table_id = aws_route_table.private_app_rt_1.id
}

resource "aws_route_table_association" "private_app_subnet_2_assoc" {
  subnet_id      = aws_subnet.private_app_subnet_2.id
  route_table_id = aws_route_table.private_app_rt_2.id
}


# =============== private route table - db tier (no internet route, isolated) ===============
resource "aws_route_table" "private_db_rt" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name}-private-db-rt"
  }
}

resource "aws_route_table_association" "private_db_subnet_1_assoc" {
  subnet_id      = aws_subnet.private_db_subnet_1.id
  route_table_id = aws_route_table.private_db_rt.id
}

resource "aws_route_table_association" "private_db_subnet_2_assoc" {
  subnet_id      = aws_subnet.private_db_subnet_2.id
  route_table_id = aws_route_table.private_db_rt.id
}
