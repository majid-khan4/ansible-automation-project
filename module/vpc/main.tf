# =========================================================
# 1️⃣ Get available Availability Zones dynamically
# =========================================================
data "aws_availability_zones" "available" {
  state = "available"
}

# =========================================================
# 2️⃣ Create VPC
# =========================================================
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name}-vpc"
  }
}

# =========================================================
# 3️⃣ Public Subnets
# =========================================================
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.main.id
  cidr_block = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name}-private-${count.index + 1}"
  }
}

# =========================================================
# 3️⃣ Private Subnets
# =========================================================
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)
  vpc_id = aws_vpc.main.id
  cidr_block = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-public-${count.index + 1}"
  }
}


# =========================================================
# 5️⃣ Internet Gateway (IGW)
# =========================================================
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name}-igw"
  }
}

# =========================================================
# 6️⃣ Elastic IP for NAT Gateway
# =========================================================
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.name}-nat-eip"
  }
}

# =========================================================
# 7️⃣ NAT Gateway in the first public subnet
# =========================================================
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.name}-nat-gateway"
  }

  depends_on = [aws_internet_gateway.igw]
}

# =========================================================
# 8️⃣ Public Route Table (routes to Internet Gateway)
# =========================================================
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.name}-public-rt"
  }
}

# =========================================================
# 9️⃣ Associate Public Subnets with Public Route Table
# =========================================================
resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# =========================================================
# 🔟 Private Route Table (routes to NAT Gateway)
# =========================================================
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "${var.name}-private-rt"
  }
}

# =========================================================
# 1️⃣1️⃣ Associate Private Subnets with Private Route Table
# =========================================================
resource "aws_route_table_association" "private_assoc" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}


# TLS keypair and private key file
resource "tls_private_key" "keypair" {
	algorithm = "RSA"
	rsa_bits  = 4096
}

resource "aws_key_pair" "public_key" {
	key_name   = "${var.name}-keypair"
	public_key = tls_private_key.keypair.public_key_openssh
}

resource "local_file" "private_key" {
	content  = tls_private_key.keypair.private_key_pem
	filename = "${var.name}-keypair.pem"
	file_permission = "0600"
}

