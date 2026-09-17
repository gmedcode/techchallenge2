resource "tls_private_key" "eks_nodes" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "eks_nodes" {
  key_name   = "${var.cluster_name}-key"
  public_key = tls_private_key.eks_nodes.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.eks_nodes.private_key_pem
  filename        = "${path.module}/${var.cluster_name}-key.pem"
  file_permission = "0600"
}