#!/bin/bash
# Create the S3 bucket that holds Terraform state. Idempotent. Needs AWS credentials in the environment.
# Prints the bucket name on the last line. Uses S3 native locking (Terraform >= 1.10), so no DynamoDB table.
set -eu
region=${AWS_DEFAULT_REGION:-us-east-1}
account=$(aws sts get-caller-identity --query Account --output text)
bucket="ship-it-demo-tfstate-$account"
if ! aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
  if [[ "$region" == us-east-1 ]]; then aws s3api create-bucket --bucket "$bucket" >/dev/null
  else aws s3api create-bucket --bucket "$bucket" --region "$region" --create-bucket-configuration LocationConstraint="$region" >/dev/null; fi
fi
aws s3api put-bucket-versioning --bucket "$bucket" --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$bucket" --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-encryption --bucket "$bucket" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
echo "$bucket"
