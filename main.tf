terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.0.2"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "docker" {}

provider "aws" {
  region = "us-west-2"

  default_tags {
    tags = {
      CreatedBy = "terraform"
    }
  }
}

resource "aws_ecs_cluster" "cluster" {
  name = "demo-cluster"
}

resource "aws_ecs_cluster_capacity_providers" "cluster" {
  cluster_name       = aws_ecs_cluster.cluster.name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

resource "aws_ecs_service" "ecs_service" {
  name            = "demo-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.ecs_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    assign_public_ip = true
    security_groups = [
      aws_security_group.websg.id
    ]
    subnets = [
      aws_subnet.private_west_a.id,
      aws_subnet.private_west_b.id,
    ]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.instance.arn
    container_name   = "container-definition"
    container_port   = var.container_port
  }
}

resource "aws_ecs_task_definition" "ecs_task" {
  family       = "service"
  network_mode = "awsvpc"

  requires_compatibilities = ["FARGATE", "EC2"]

  cpu    = 512
  memory = 2048

  container_definitions = jsonencode([
    {
      # name      = "ubuntu"
      # image     = "ubuntu:22.04"
      name  = "container-definition"
      image = join("@", [aws_ecr_repository.instance.repository_url, data.aws_ecr_image.instance.image_digest])

      essential = true
      portMappings = [
        {
          containerPort = var.container_port
          # hostPort = var.container_port
        }
      ]
    },
  ])

  execution_role_arn = aws_iam_role.ecs_execution_role.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
}

resource "aws_vpc" "demo_ecs" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "Demo ECS"
  }
}

resource "aws_subnet" "private_west_a" {
  vpc_id            = aws_vpc.demo_ecs.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"

  tags = {
    Name = "Private West A"
  }
}
resource "aws_subnet" "private_west_b" {
  vpc_id            = aws_vpc.demo_ecs.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2b"

  tags = {
    Name = "Private West B"
  }
}

output "aws_ecs_cluster" {
  value       = aws_ecs_cluster.cluster.name
  description = "name of the cluster"
}

output "aws_ecs_cluster_capacity_providers" {
  value       = aws_ecs_cluster_capacity_providers.cluster.capacity_providers
  description = "compute serverless engine for ECS"
}

output "ecr_repository_name" {
  value = aws_ecr_repository.instance.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.instance.repository_url
}

output "alb_dns" {
  value = aws_lb.instance.dns_name
}

resource "aws_ecr_repository" "instance" {
  name = "ecr-repository"
}

data "aws_ecr_repository" "instance" {
  name = aws_ecr_repository.instance.name
}

data "aws_ecr_image" "instance" {
  repository_name = aws_ecr_repository.instance.name
  image_tag       = "init"
}

resource "aws_lb" "instance" {
  name               = "alb"
  load_balancer_type = "application"
  subnets = [
    aws_subnet.mysbnt_a.id,
    aws_subnet.mysbnt_b.id
  ]
}

resource "aws_lb_listener" "instance" {
  load_balancer_arn = aws_lb.instance.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.instance.arn
  }
}

resource "aws_lb_target_group" "instance" {
  name                 = "alb-target-group"
  target_type          = "ip"
  protocol             = "HTTP"
  port                 = var.container_port
  vpc_id               = aws_vpc.demo_ecs.id
  deregistration_delay = 30 // seconds
  health_check {
    interval          = 5 // seconds
    timeout           = 2 // seconds
    healthy_threshold = 2
    protocol          = "HTTP"
    path              = "/"
  }
}

resource "aws_subnet" "mysbnt_a" {
  vpc_id                  = aws_vpc.demo_ecs.id
  cidr_block              = "10.0.6.0/24"
  availability_zone       = "us-west-2a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "mysbnt_b" {
  vpc_id                  = aws_vpc.demo_ecs.id
  cidr_block              = "10.0.8.0/24"
  availability_zone       = "us-west-2b"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.demo_ecs.id

  tags = {
    Name = "igw"
  }
}

resource "aws_security_group" "websg" {
  name = "websg"

  description = "ECS server (terraform-managed)"
  vpc_id      = aws_vpc.demo_ecs.id
  depends_on = [
    aws_vpc.demo_ecs
  ]

  # All HTTP traffic in
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ingress {
  #   protocol    = "tcp"
  #   from_port   = 443
  #   to_port     = 443
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  # # Allow SSH access
  # ingress {
  #   from_port = 22
  #   to_port = 22
  #   protocol = "tcp"
  #   cidr_blocks = []
  # }

  # Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "websg"
  }
}

resource "aws_security_group" "ecs_tasks" {
  name   = "demo_sg_task"
  vpc_id = aws_vpc.demo_ecs.id
  depends_on = [
    aws_vpc.demo_ecs
  ]

  ingress {
    protocol    = "tcp"
    from_port   = var.container_port
    to_port     = var.container_port
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

variable "container_port" {
  default = 8400
  type    = number
}

resource "aws_ecr_lifecycle_policy" "main" {
  repository = aws_ecr_repository.instance.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep last 10 images"
      action = {
        type = "expire"
      }
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
    }]
  })
}
