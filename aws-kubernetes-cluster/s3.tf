# S3 Bucket to publicly host your cluster's OIDC discovery documents
resource "aws_s3_bucket" "k8s_bucket" {
  bucket = "k8s-admin-${substr(data.aws_caller_identity.current.account_id, -4, 4)}"
  # Delete with data
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "oidc_public" {
  bucket = aws_s3_bucket.k8s_bucket.id

  block_public_acls       = false
  ignore_public_acls      = false
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "oidc_bucket_policy" {
  depends_on = [
    aws_s3_bucket.k8s_bucket,
    aws_s3_bucket_public_access_block.oidc_public
  ]
  bucket = aws_s3_bucket.k8s_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicGetPut"
      Effect    = "Allow"
      Principal = "*"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
      ]
      Resource = [
        "arn:aws:s3:::${aws_s3_bucket.k8s_bucket.id}/.well-known/openid-configuration",
        "arn:aws:s3:::${aws_s3_bucket.k8s_bucket.id}/openid/v1/jwks",
        "arn:aws:s3:::${aws_s3_bucket.k8s_bucket.id}/k8s_setup/*",
        "arn:aws:s3:::${aws_s3_bucket.k8s_bucket.id}/k8s_manifest/*"
      ]
    }]
  })
}

# Register S3 OIDC Endpoint with AWS IAM
resource "aws_iam_openid_connect_provider" "register_oidc" {
  depends_on = [
    terraform_data.config_oidc
  ]
  url            = "https://${aws_s3_bucket.k8s_bucket.bucket}.s3.${data.aws_region.current.region}.amazonaws.com"
  client_id_list = ["sts.amazonaws.com"]
}