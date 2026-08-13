module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Acesso à API do cluster. Padrão deste lab: SOMENTE PRIVADO.
  # ⚠️ Com endpoint privado, kubectl/Terraform (providers kubernetes/helm) precisam
  #    rodar de DENTRO da VPC (bastion EC2 ou VPN). O único ponto exposto à
  #    internet é o ALB do Ingress (exposição via LB).
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  cluster_endpoint_private_access      = var.cluster_endpoint_private_access

  # 🔑 IRSA: cria e associa o OIDC provider do cluster à AWS.
  # É o que permite um ServiceAccount assumir uma Role do IAM (sem chaves estáticas).
  enable_irsa = true

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Dá ao usuário/role que roda o Terraform acesso admin ao cluster (EKS Access Entries).
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    workers = {
      instance_types = [var.node_instance_type]
      capacity_type  = var.capacity_type # SPOT no lab para reduzir custo

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      labels = {
        role = "workers"
      }
    }
  }

  # Add-ons gerenciados. O VPC CNI suporta Network Policies de forma nativa
  # (alternativa ao Calico) — habilitamos aqui para o módulo de governança funcionar.
  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
      })
    }
  }
}
