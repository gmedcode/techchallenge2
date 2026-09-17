# ---------------------------------------------------------------------------
# GitHub Actions OIDC — lets GitHub Actions authenticate to AWS without
# storing long-lived access keys as GitHub Secrets. GitHub Actions requests
# a short-lived token from AWS STS, scoped to this specific repo.
#
# Requires var.github_username to be supplied at apply-time:
#   terraform apply -var="github_username=<your-github-username>"
# ---------------------------------------------------------------------------

# GitHub's own OIDC provider (same URL/thumbprint for every GitHub user —
# not specific to this account)
resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# IAM role GitHub Actions will assume — scoped specifically to this repo
resource "aws_iam_role" "github_actions" {
  name = "${var.cluster_name}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github_actions.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # Scopes this role so ONLY workflows running from your repo
          # (any branch) can assume it
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_username}*/techchallenge2*:*"
        }
      }
    }]
  })
}

# Allows GitHub Actions to push images to ECR
resource "aws_iam_role_policy_attachment" "github_actions_ecr" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
