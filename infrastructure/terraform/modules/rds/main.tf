# RDS module. The single most important decision here: there is NO
# db_password variable. manage_master_user_password = true tells RDS to
# generate the password itself and store it directly in AWS Secrets Manager
# - it never appears in a .tfvars file, a variable, a plan, or Terraform
# state. This is meaningfully better than the common pattern of a
# `sensitive = true` Terraform variable, which still writes the plaintext
# password into the state file (sensitive only hides it from CLI output).
# The External Secrets Operator (noted in Phase 1's architecture doc) reads
# straight from the Secrets Manager ARN this module outputs.

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = var.tags
}

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds-sg"
  description = "Allow Postgres access only from EKS nodes"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Postgres from EKS cluster"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_cluster_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name}-postgres"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage # enables storage autoscaling up to this ceiling
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.master_username

  # See module header - no password variable, RDS + Secrets Manager own it.
  manage_master_user_password = true

  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = [aws_security_group.rds.id]

  multi_az = var.multi_az

  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00" # UTC, low-traffic window
  maintenance_window      = "mon:04:30-mon:05:30"

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-postgres-final-snapshot"

  tags = var.tags
}
