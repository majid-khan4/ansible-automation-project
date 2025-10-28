# create base subnet group
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "${var.name}-db-subnet-group"
  subnet_ids = var.db_subnets

  tags = {
    Name = "${var.name}-db-subnet-group"
  }
}

# create security group for RDS database
resource "aws_security_group" "db_sg" {
  name        = "${var.name}-db-sg"
  description = "Security group for RDS database"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow DB access from stage and prod instances"
    from_port       = 3306  
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.stage_sg, var.prod_sg]
    }
    egress {
    description = "Allow all outbound traffic"
    from_port   = 0 
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  } 
  tags = {
    Name = "${var.name}-db-sg"
  }
}

# create the RDS MySQL database instance
resource "aws_db_instance" "mysql_db" {
  identifier              = "${var.name}-mysql-db"
  allocated_storage       = 10
  engine                  = "mysql"
  engine_version          = "8.0.36"
  instance_class          = "db.t3.micro"
  parameter_group_name    = "default.mysql5.7"
  db_name                 = "petclinic"
  username                = var.db_username
  password                = var.db_password
  skip_final_snapshot     = true
  db_subnet_group_name    = aws_db_subnet_group.db_subnet_group.id
  vpc_security_group_ids  = [aws_security_group.db_sg.id]
  multi_az                = false
  publicly_accessible     = false

  tags = {
    Name = "${var.name}-mysql-db"
  }
}   