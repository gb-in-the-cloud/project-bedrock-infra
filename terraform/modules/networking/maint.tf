# Networking Module — project-bedrock-vpc
# Creates:
#   - VPC tagged Name: project-bedrock-vpc (assessed naming)
#   - 2 public subnets across 2 AZs  (ALB, NAT Gateway)
#   - 2 private subnets across 2 AZs (EKS worker nodes)
#   - 1 NAT Gateway (cost guardrail — assessed requirement)
#   - Internet Gateway
#   - Route tables for public and private traffic

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true # Required for EKS node registration
  enable_dns_support   = true # Required for EKS service discovery

  tags = {
    Name = "${var.project_name}-vpc"
    # Kubernetes tags — required for ALB auto-discovery
    "kubernetes.io/cluster/${var.project_name}-cluster" = "shared"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

# ── Public Subnets ────────────────────────────────────────────────────────────
resource "aws_subnet" "public" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${var.availability_zones[count.index]}"
    # AWS Load Balancer Controller uses this tag to place internet-facing ALBs
    "kubernetes.io/role/elb"                            = "1"
    "kubernetes.io/cluster/${var.project_name}-cluster" = "shared"
  }
}

# ── Private Subnets ───────────────────────────────────────────────────────────
resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-private-${var.availability_zones[count.index]}"
    # AWS Load Balancer Controller uses this tag to place internal ALBs
    "kubernetes.io/role/internal-elb"                   = "1"
    "kubernetes.io/cluster/${var.project_name}-cluster" = "shared"
  }
}

# ── NAT Gateway (SINGLE — cost guardrail) ─────────────────────────────────────
resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]
  tags       = { Name = "${var.project_name}-nat-eip" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id # First public subnet only

  depends_on = [aws_internet_gateway.main]
  tags       = { Name = "${var.project_name}-nat" }
}

# ── Route Tables ──────────────────────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = { Name = "${var.project_name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}