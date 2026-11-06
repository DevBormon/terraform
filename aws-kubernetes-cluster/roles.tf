/*
 sts: Security Token Service
 data: Tells Terraform that we are defining or reading a data object
 aws_iam_policy_document: An AWS Terraform data source that helps generate IAM policy JSON.

 Principal = WHO can access?
 Action = WHAT can they do?
 Resource = WHICH resource can they access?
 Condition = UNDER WHAT CONDITIONS can they access?
 
 An IAM role has two important things:
    Trust policy – Who can assume this role?
    Permission policy – What can the role do after assuming it?
  
  What is a principal?

  A principal is the identity that is allowed to perform an action.

  For example:
      IAM user
      IAM role
      AWS service
      Federated identity
*/
data "aws_iam_policy_document" "master_role_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "karpenter_role_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type = "Federated"
      identifiers = [
        aws_iam_openid_connect_provider.register_oidc.arn
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.register_oidc.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${local.karpenter_ns}:${local.karpenter_service_account_name}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.register_oidc.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "master_role" {
  name                  = "k8s-master-role"
  assume_role_policy    = data.aws_iam_policy_document.master_role_policy.json
  force_detach_policies = true
}

resource "aws_iam_role" "worker_role" {
  name = "k8s-worker-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  force_detach_policies = true
}

resource "aws_iam_role" "karpenter_role" {
  name               = "k8s-karpenter-role"
  assume_role_policy = data.aws_iam_policy_document.karpenter_role_policy.json
}

# Policy for MASTER role
resource "aws_iam_role_policy" "master_policy" {
  name = "k8s-master-policy"
  role = aws_iam_role.master_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowWriteParametersAndAddTags"
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:AddTagsToResource"
        ]
        Resource = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_parameter_path}"
      },
      {
        Sid    = "ListK8sSetupAndManifestFiles"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.k8s_bucket.id}"
        ]
      },
      {
        Sid    = "ManageK8sSetupAndManifestObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.k8s_bucket.id}/k8s_setup/*",
          "arn:aws:s3:::${aws_s3_bucket.k8s_bucket.id}/k8s_manifest/*"
        ]
      }
    ]
  })
}

# Policy for WORKER role
resource "aws_iam_role_policy" "worker_policy" {
  name = "k8s-worker-policy"
  role = aws_iam_role.worker_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AllowReadParameter"
      Effect   = "Allow"
      Action   = "ssm:GetParameter"
      Resource = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_parameter_path}"
      },
      {
        Sid    = "ListK8sSetupAndManifestFiles"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.k8s_bucket.id}"
        ]
      },
      {
        Sid    = "GetK8sSetupAndManifestObjects"
        Effect = "Allow"
        Action = "s3:GetObject"
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.k8s_bucket.id}/k8s_setup/*",
          "arn:aws:s3:::${aws_s3_bucket.k8s_bucket.id}/k8s_manifest/*"
        ]
      }
    ]
  })
}

# Karpenter Controller Permissions Policy
resource "aws_iam_policy" "karpenter_policy" {
  name        = "k8s-karpenter-policy"
  description = "Allows Karpenter controller to manage EC2 instances"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Node Lifecycle Policy
      {
        Sid    = "KarpenterInstanceAccess"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet"
        ]
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.region}::image/*",
          "arn:aws:ec2:${data.aws_region.current.region}::snapshot/*",
          "arn:aws:ec2:${data.aws_region.current.region}:*:security-group/*",
          "arn:aws:ec2:${data.aws_region.current.region}:*:subnet/*",
          "arn:aws:ec2:${data.aws_region.current.region}:*:capacity-reservation/*",
          "arn:aws:ec2:${data.aws_region.current.region}:*:placement-group/*"
        ]
      },
      {
        Sid    = "KarpenterLaunchTemplateAccess"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet"
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${local.cluster_name}" = "owned"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          }
        }
        Resource = "arn:aws:ec2:${data.aws_region.current.region}:*:launch-template/*"
      },
      {
        Sid    = "KarpenterInstanceWithTags"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${local.cluster_name}" = "owned"
          }

          StringLike = {
            "aws:RequestTag/karpenter.sh/nodepool" = "*"
          }
        }
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.region}:*:fleet/*",
          "arn:aws:ec2:${data.aws_region.current.region}:*:instance/*",
          "arn:aws:ec2:${data.aws_region.current.region}:*:volume/*",
          "arn:aws:ec2:${data.aws_region.current.region}:*:network-interface/*",
          "arn:aws:ec2:${data.aws_region.current.region}:*:launch-template/*",
          "arn:aws:ec2:${data.aws_region.current.region}:*:spot-instances-request/*"
        ]
      },
      {
        Sid    = "KarpenterResourceCreationTagging"
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${local.cluster_name}" : "owned",
            "ec2:CreateAction" = [
              "RunInstances",
              "CreateFleet",
              "CreateLaunchTemplate"
            ]
          }
          StringLike = {
            "aws:RequestTag/karpenter.sh/nodepool" : "*"
          }
        }
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.region}:*:fleet/*",
          "arn:aws:ec2:${data.aws_region.current.region}:*:instance/*",
          "arn:aws:ec2:${data.aws_region.current.region}:*:volume/*",
          "arn:aws:ec2:${data.aws_region.current.region}:*:network-interface/*",
          "arn:aws:ec2:${data.aws_region.current.region}:*:launch-template/*",
          "arn:aws:ec2:${data.aws_region.current.region}:*:spot-instances-request/*"
        ]
      },
      {
        Sid    = "KarpenterResourceTagging"
        Effect = "Allow"
        Action = "ec2:CreateTags"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${local.cluster_name}" : "owned"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" : "*"
          }
          "ForAllValues:StringEquals" = {
            "aws:TagKeys" = [
              "karpenter.sh/nodeclaim",
              "Name"
            ]
          }
        }
        Resource = "arn:aws:ec2:${data.aws_region.current.region}:*:instance/*"
      },
      {
        Sid    = "KarpenterDeletion"
        Effect = "Allow"
        Action = [
          "ec2:TerminateInstances",
          "ec2:RebootInstances",
          "ec2:DeleteLaunchTemplate"
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${local.cluster_name}" : "owned"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" : "*"
          }
        }
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.region}:*:instance/*",
          "arn:aws:ec2:${data.aws_region.current.region}:*:launch-template/*"
        ]
      },
      # IAM Integration Policy
      {
        Sid    = "KarpenterPassingInstanceRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = [
              "ec2.amazonaws.com",
              "ec2.amazonaws.com.cn"
            ]
          }
        }
        Resource = aws_iam_role.worker_role.arn
      },
      {
        Sid    = "KarpenterInstanceProfileCreation"
        Effect = "Allow"
        Action = "iam:CreateInstanceProfile"
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${local.cluster_name}" : "owned",
            "aws:RequestTag/topology.kubernetes.io/region" : "${data.aws_region.current.region}"
          }
          StringLike = {
            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass" : "*"
          }
        }
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
      },
      {
        Sid    = "KarpenterInstanceProfileTag"
        Effect = "Allow"
        Action = "iam:TagInstanceProfile"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${local.cluster_name}" : "owned",
            "aws:ResourceTag/topology.kubernetes.io/region" : "${data.aws_region.current.region}",
            "aws:RequestTag/kubernetes.io/cluster/${local.cluster_name}" : "owned",
            "aws:RequestTag/topology.kubernetes.io/region" : "${data.aws_region.current.region}"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" : "*",
            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass" : "*"
          }
        }
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
      },
      {
        Sid    = "KarpenterInstanceProfile"
        Effect = "Allow"
        Action = [
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:DeleteInstanceProfile"
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${local.cluster_name}" : "owned",
            "aws:ResourceTag/topology.kubernetes.io/region" : "${data.aws_region.current.region}"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" : "*"
          }
        }
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
      },
      # Resource Discovery Policy
      {
        Sid    = "KarpenterRegionalReadActions"
        Effect = "Allow"
        Action = [
          "ec2:DescribeCapacityReservations",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribePlacementGroups",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" : "${data.aws_region.current.region}"
          }
        }
        Resource = "*"
      },
      {
        Sid      = "KarpenterSSMRead"
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = "arn:aws:ssm:${data.aws_region.current.region}::parameter/aws/service/*"
      },
      {
        Sid      = "KarpenterPricingRead"
        Effect   = "Allow"
        Action   = "pricing:GetProducts"
        Resource = "*"
      },
      {
        Sid      = "KarpenterUnscopedInstanceProfileList"
        Effect   = "Allow"
        Action   = "iam:ListInstanceProfiles"
        Resource = "*"
      },
      {
        Sid      = "KarpenterInstanceProfileRead"
        Effect   = "Allow"
        Action   = "iam:GetInstanceProfile"
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_attach" {
  role       = aws_iam_role.karpenter_role.name
  policy_arn = aws_iam_policy.karpenter_policy.arn
}

# profiling for master
resource "aws_iam_instance_profile" "master_profile" {
  name = "k8s-master-profile"
  role = aws_iam_role.master_role.name
}

# profiling for worker
resource "aws_iam_instance_profile" "worker_profile" {
  name = "k8s-worker-profile"
  role = aws_iam_role.worker_role.name
}
