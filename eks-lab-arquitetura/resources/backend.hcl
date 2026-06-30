# Config de backend COMPARTILHADA por todos os stacks.
# Edite o bucket/tabela UMA vez aqui e use em cada stack:
#   terraform init -backend-config=../backend.hcl
#
# A 'key' (caminho do state) é definida no versions.tf de cada stack.
bucket         = "SEU-BUCKET-TFSTATE"
region         = "us-east-1"
dynamodb_table = "terraform-locks"
encrypt        = true
