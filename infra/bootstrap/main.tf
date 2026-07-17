locals {
  github_repo  = "jameskehs/sre-dummy-project"
  state_bucket = "sre-dummy-project-tfstate"

  # ARNs of the workload IAM entities that the app config (../) creates.
  # Bootstrap can't reference them directly (they live in a different state),
  # so we reconstruct them from their known names.
  instance_role_arn    = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/app-instance-role"
  instance_profile_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/app-instance-profile"
}

data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "app_oidc_provider" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]
}

# ---------------------------------------------------------------------------
# Apply role — assumed only by workflows running on the main branch.
# Merges to main run `terraform apply`, so this role can mutate infra.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "app_apply_role" {
  name = "app-apply-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.app_oidc_provider.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:${local.github_repo}:ref:refs/heads/main"
          }
        }
      },
    ]
  })

  tags = {
    Name = "SRE-DUMMY-APP-APPLY-ROLE"
  }
}

# ---------------------------------------------------------------------------
# Plan role — assumed only by pull_request workflows.
# PRs run `terraform plan` (the gate) and must NOT be able to change anything.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "app_plan_role" {
  name = "app-plan-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.app_oidc_provider.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:${local.github_repo}:pull_request"
          }
        }
      },
    ]
  })

  tags = {
    Name = "SRE-DUMMY-APP-PLAN-ROLE"
  }
}

# ---------------------------------------------------------------------------
# Deployment policy — for the APPLY role. Full lifecycle on the compute/
# network/LB services, but IAM and state access are tightly scoped.
# ---------------------------------------------------------------------------
resource "aws_iam_policy" "app_deployment_policy" {
  name = "app-deployment-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # EC2 / ELB / ASG kept at service level: EC2 resource-level IAM is
      # impractical for VPC/subnet/SG/route-table creation. Documented as a
      # deliberate simplification; production would scope these down.
      {
        Sid      = "NetworkingAndCompute"
        Effect   = "Allow"
        Action   = "ec2:*"
        Resource = "*"
      },
      {
        Sid      = "LoadBalancing"
        Effect   = "Allow"
        Action   = "elasticloadbalancing:*"
        Resource = "*"
      },
      {
        Sid      = "AutoScaling"
        Effect   = "Allow"
        Action   = "autoscaling:*"
        Resource = "*"
      },
      # IAM: write actions limited to the two named workload entities only.
      {
        Sid    = "ManageWorkloadIamEntities"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:UntagInstanceProfile",
        ]
        Resource = [
          local.instance_role_arn,
          local.instance_profile_arn,
        ]
      },
      # PassRole: the launch template hands the instance profile to EC2.
      # Restrict to the one role and only when passed to EC2.
      {
        Sid      = "PassInstanceRoleToEc2"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = local.instance_role_arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ec2.amazonaws.com"
          }
        }
      },
      # IAM reads needed during refresh (managed policies are AWS-owned, so "*").
      {
        Sid    = "ReadIamForRefresh"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:GetInstanceProfile",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
        ]
        Resource = "*"
      },
      # Remote state: read + write state object and the S3 lock file.
      {
        Sid    = "TerraformStateWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "arn:aws:s3:::${local.state_bucket}/*"
      },
      {
        Sid      = "TerraformStateList"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::${local.state_bucket}"
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# PR policy — for the PLAN role. Read-only. A PR literally cannot mutate
# infrastructure or state. Run `terraform plan -lock=false` in the PR job so
# no S3 write (lock file) is ever attempted.
# ---------------------------------------------------------------------------
resource "aws_iam_policy" "app_pr_policy" {
  name = "app-pr-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeInfrastructure"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "elasticloadbalancing:Describe*",
          "autoscaling:Describe*",
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadIam"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:GetInstanceProfile",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
        ]
        Resource = "*"
      },
      # Read-only state access: read the state object, list the bucket.
      # No PutObject/DeleteObject, so no lock can be taken (hence -lock=false).
      {
        Sid      = "TerraformStateRead"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::${local.state_bucket}/*"
      },
      {
        Sid      = "TerraformStateList"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::${local.state_bucket}"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "apply_permissions" {
  role       = aws_iam_role.app_apply_role.name
  policy_arn = aws_iam_policy.app_deployment_policy.arn
}

resource "aws_iam_role_policy_attachment" "plan_permissions" {
  role       = aws_iam_role.app_plan_role.name
  policy_arn = aws_iam_policy.app_pr_policy.arn
}
