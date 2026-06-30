# =============================================================================
# Bastion EC2 para acessar o cluster EKS PRIVADO.
#
# Acesso via AWS Systems Manager (SSM Session Manager): sem porta 22 aberta,
# sem chave SSH. A instância fica em subnet PRIVADA e alcança o SSM pelo NAT.
#
# Para conseguir falar com o endpoint privado da API do EKS, a instância também
# entra no Security Group do cluster (que permite tráfego interno na 443).
# =============================================================================

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---- IAM: permite o SSM (acesso) e o describe do cluster (kubeconfig) ----
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "eks_describe" {
  name = "${var.name}-eks-describe"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["eks:DescribeCluster", "eks:ListClusters"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-profile"
  role = aws_iam_role.this.name
}

# ---- Security Group próprio do bastion (apenas saída) ----
resource "aws_security_group" "this" {
  name        = "${var.name}-sg"
  description = "Bastion EC2 - egress only (acesso via SSM)"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-sg"
  }
}

# ---- A instância ----
resource "aws_instance" "this" {
  ami                  = data.aws_ssm_parameter.al2023.value
  instance_type        = var.instance_type
  subnet_id            = var.subnet_id
  iam_instance_profile = aws_iam_instance_profile.this.name
  # SG próprio + SG do cluster (libera 443 do endpoint privado da API).
  vpc_security_group_ids = [aws_security_group.this.id, var.cluster_security_group_id]

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    # kubectl
    curl -sLO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    # helm
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    # aws cli v2
    dnf install -y unzip || yum install -y unzip
    curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install --update
  EOF

  metadata_options {
    http_tokens = "required" # IMDSv2
  }

  tags = {
    Name = var.name
  }
}

# =============================================================================
# VPC endpoints de SSM (opcionais).
# Permitem que o SSM Session Manager funcione mesmo sem NAT, pois o tráfego do
# agente SSM passa por endpoints privados de interface dentro da VPC.
# (Obs.: o user_data ainda baixa kubectl/helm da internet — isso usa o NAT.)
# =============================================================================
locals {
  ssm_services = var.create_ssm_endpoints ? toset(["ssm", "ssmmessages", "ec2messages"]) : toset([])
}

resource "aws_security_group" "endpoints" {
  count       = var.create_ssm_endpoints ? 1 : 0
  name        = "${var.name}-ssm-endpoints-sg"
  description = "Permite 443 para os VPC endpoints de SSM"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS de dentro da VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-ssm-endpoints-sg"
  }
}

data "aws_region" "current" {}

resource "aws_vpc_endpoint" "ssm" {
  for_each = local.ssm_services

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.endpoint_subnet_ids
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true

  tags = {
    Name = "${var.name}-${each.value}"
  }
}
