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


variable "aws_region" {
  default = "us-west-2"
  type    = string
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      CreatedBy = "terraform"
    }
  }
}

resource "aws_ecs_cluster" "cluster" {
  name = "demo-cluster"

  # setting {
  #   name  = "containerInsights"
  #   value = "enabled"
  # }
}

locals {
  ecs_service_name = "demo-service"
}

resource "aws_ecs_service" "ecs_service" {
  name            = local.ecs_service_name
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.ecs_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    assign_public_ip = true
    security_groups = [
      aws_security_group.service_sg.id
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

  depends_on = [aws_lb_listener.instance]
}

resource "aws_ecs_task_definition" "ecs_task" {
  family       = "service"
  network_mode = "awsvpc"

  requires_compatibilities = ["FARGATE"]

  execution_role_arn = aws_iam_role.ecs_execution_role.arn
  task_role_arn      = aws_iam_role.task_definition_role.arn

  cpu    = 512
  memory = 2048

  container_definitions = jsonencode([
    {
      # name      = "ubuntu"
      # image     = "ubuntu:22.04"
      name  = "container-definition"
      image = join("@", [aws_ecr_repository.instance.repository_url, data.aws_ecr_image.instance.image_digest])

      essential = true

      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = aws_cloudwatch_log_group.log_group.id
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "demo"
        }
      },
      portMappings = [
        {
          containerPort = var.container_port
          # hostPort = var.container_port
        }
      ]
    }
  ])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  tags = {
    Name = "demo-ecs-td"
  }
}

# resource "aws_appautoscaling_target" "instance" {
#   max_capacity       = 5
#   min_capacity       = 1
#   resource_id        = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.ecs_service.name}"
#   service_namespace  = "ecs"
#   scalable_dimension = "ecs:service:DesiredCount"
# }

# resource "aws_appautoscaling_policy" "instance" {
#   name               = "ecs-cpu-auto-scaling"
#   policy_type        = "TargetTrackingScaling"
#   service_namespace  = aws_appautoscaling_target.instance.service_namespace
#   scalable_dimension = aws_appautoscaling_target.instance.scalable_dimension
#   resource_id        = aws_appautoscaling_target.instance.resource_id

#   target_tracking_scaling_policy_configuration {
#     predefined_metric_specification {
#       predefined_metric_type = "ECSServiceAverageCPUUtilization"
#     }

#     target_value       = 80
#     scale_in_cooldown  = 300
#     scale_out_cooldown = 300
#   }
# }

# resource "aws_ecs_cluster_capacity_providers" "cluster" {
#   cluster_name       = aws_ecs_cluster.cluster.name
#   capacity_providers = ["FARGATE"]

#   default_capacity_provider_strategy {
#     base              = 1
#     weight            = 100
#     capacity_provider = "FARGATE"
#   }
# }

output "aws_ecs_cluster" {
  value       = aws_ecs_cluster.cluster.name
  description = "name of the cluster"
}

# output "aws_ecs_cluster_capacity_providers" {
#   value       = aws_ecs_cluster_capacity_providers.cluster.capacity_providers
#   description = "compute serverless engine for ECS"
# }

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
    aws_subnet.public_west_a.id,
    aws_subnet.public_west_b.id
  ]
  security_groups = [aws_security_group.load_balancer_sg.id]
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

resource "aws_cloudwatch_log_group" "log_group" {
  name = "demo-logs"

  tags = {
    Application = "demo"
  }
}

resource "aws_vpc" "demo_ecs" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "Demo ECS"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.demo_ecs.id

  tags = {
    Name = "igw"
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

resource "aws_subnet" "public_west_a" {
  vpc_id                  = aws_vpc.demo_ecs.id
  cidr_block              = "10.0.6.0/24"
  availability_zone       = "us-west-2a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_west_b" {
  vpc_id                  = aws_vpc.demo_ecs.id
  cidr_block              = "10.0.8.0/24"
  availability_zone       = "us-west-2b"
  map_public_ip_on_launch = true
}


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.demo_ecs.id

  tags = {
    Name = "routing-table-public"
  }
}

resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_west_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_west_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "service_sg" {
  name        = "service_sg"
  description = "ECS server (terraform-managed)"

  vpc_id = aws_vpc.demo_ecs.id
  depends_on = [
    aws_vpc.demo_ecs
  ]

  # All HTTP traffic in
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "tcp"
    security_groups = [aws_security_group.load_balancer_sg.id]
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
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "service_sg"
  }
}

resource "aws_security_group" "load_balancer_sg" {
  vpc_id = aws_vpc.demo_ecs.id

  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "demo-sg"
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
