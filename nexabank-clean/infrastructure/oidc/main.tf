provider "aws" {
  region = "af-south-1" 
}

#GitHub OIDC Identity Provider
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"] # Standard GitHub OIDC TLS thumbprint
}

#Trust Policy restricting access specifically to repository and branches
data "aws_iam_policy_document" "github_oidc_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrict assumption strictly to GitHub repo
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:akinsilecloudops@275244958/identityforge-nexabank@1401289726:*"]
    }
  }
}

#IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions" {
  name               = "nexabank-github-actions-role"
  assume_role_policy = data.aws_iam_policy_document.github_oidc_trust.json
  description        = "IAM role assumed securely by GitHub Actions via OIDC for automated deployments."
}

resource "aws_iam_role_policy_attachment" "oidc_permissions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess" 
}

output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions.arn
  description = "Used in GitHub Actions workflow file under role-to-assume."
}