# VPC module: public/private subnets across N AZs, one NAT strategy that
# handles both dev (single shared NAT, cheap) and production (one NAT per AZ,
# resilient) from the same code - controlled entirely by var.single_nat_gateway.

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${var.name}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-igw"
  })
}

# --- Public subnets: one per AZ. ALB and NAT Gateway(s) live here. ---
resource "aws_subnet" "public" {
  for_each = { for idx, az in var.azs : az => idx }

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, each.value)
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                     = "${var.name}-public-${each.key}"
    "kubernetes.io/role/elb" = "1" # required tag for AWS Load Balancer Controller subnet auto-discovery (Phase 6)
  })
}

# --- Private subnets: one per AZ. EKS nodes and RDS live here, no direct route to the internet. ---
resource "aws_subnet" "private" {
  for_each = { for idx, az in var.azs : az => idx }

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  # Offset by 100 in the second octet's subnet index so public/private CIDR
  # ranges never overlap regardless of how many AZs are in use.
  cidr_block = cidrsubnet(var.vpc_cidr, 4, each.value + 8)

  tags = merge(var.tags, {
    Name                              = "${var.name}-private-${each.key}"
    "kubernetes.io/role/internal-elb" = "1" # required tag for internal ALBs (Phase 6)
  })
}

# --- Public route table: one, shared by all public subnets ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-public-rt"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# --- NAT Gateways: 1 (dev/staging) or 1-per-AZ (production), driven by var.single_nat_gateway ---
locals {
  nat_gateway_count = var.single_nat_gateway ? 1 : length(var.azs)
}

resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name}-nat-eip-${count.index}"
  })
}

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  # Round-robins across public subnets by index - with count=1 this is
  # always the first AZ's public subnet; with count=len(azs) each NAT lands
  # in a different AZ.
  subnet_id     = aws_subnet.public[var.azs[count.index]].id
  allocation_id = aws_eip.nat[count.index].id

  tags = merge(var.tags, {
    Name = "${var.name}-nat-${count.index}"
  })

  depends_on = [aws_internet_gateway.this]
}

# --- Private route tables: one per AZ, always - even with a single shared
# NAT Gateway. This keeps the module's shape consistent between dev and
# production; only which NAT each table's default route points at changes. ---
resource "aws_route_table" "private" {
  for_each = { for idx, az in var.azs : az => idx }

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-private-rt-${each.key}"
  })
}

resource "aws_route" "private_nat" {
  for_each = aws_route_table.private

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  # index % nat_gateway_count: with 1 NAT, every AZ's table points at NAT[0].
  # With len(azs) NATs, each AZ's table points at its own dedicated NAT.
  nat_gateway_id = aws_nat_gateway.this[index(var.azs, each.key) % local.nat_gateway_count].id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}
