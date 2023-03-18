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

provider "docker" {

}

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
    subnets = [
      aws_subnet.private_west_a.id,
      aws_subnet.private_west_b.id,
    ]
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
          containerPort = 8080
          hostPort      = 80
        }
      ]
    },
  ])

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

# output "alb_dns" {
#   value = aws_lb.instance.dns_name
# }

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
