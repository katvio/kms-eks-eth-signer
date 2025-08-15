# ---------- variables (edit these) ----------
export AWS_REGION="eu-west-1"
export AWS_PROFILE="platform-admin" 
export TF_STATE_BUCKET="eth-signer-challenge-tfstate-$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-')"
export TF_LOCK_TABLE="terraform-state-locks"
# -------------------------------------------

# Set the profile and region
aws configure set region "$AWS_REGION" --profile "$AWS_PROFILE"

echo "Using AWS Profile: $AWS_PROFILE"
echo "Using AWS Region: $AWS_REGION"
echo "S3 Bucket: $TF_STATE_BUCKET"

# Verify credentials work
echo "Verifying AWS credentials..."
aws sts get-caller-identity --profile "$AWS_PROFILE"

if [ $? -ne 0 ]; then
    echo "Error: AWS credentials not working. Please check your profile setup."
    exit 1
fi

echo "Creating S3 bucket..."
if aws s3api head-bucket --bucket "$TF_STATE_BUCKET" --profile "$AWS_PROFILE" 2>/dev/null; then
    echo "✅ S3 bucket $TF_STATE_BUCKET already exists"
else
    aws s3api create-bucket \
        --bucket "$TF_STATE_BUCKET" \
        --create-bucket-configuration LocationConstraint="$AWS_REGION" \
        --profile "$AWS_PROFILE"
    echo "✅ S3 bucket $TF_STATE_BUCKET created"
fi

echo "Configuring S3 bucket..."
aws s3api put-public-access-block \
    --bucket "$TF_STATE_BUCKET" \
    --profile "$AWS_PROFILE" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Enable versioning (recommended for TF state)
aws s3api put-bucket-versioning \
    --bucket "$TF_STATE_BUCKET" \
    --profile "$AWS_PROFILE" \
    --versioning-configuration Status=Enabled

# Block all public access
echo "Configuring S3 bucket security..."
aws s3api put-public-access-block --bucket "$TF_STATE_BUCKET" --profile "$AWS_PROFILE" \
  --public-access-block-configuration \
'{
  "BlockPublicAcls": true,
  "IgnorePublicAcls": true,
  "BlockPublicPolicy": true,
  "RestrictPublicBuckets": true
}'

# Default encryption (SSE-S3). Use SSE-KMS if you prefer.
aws s3api put-bucket-encryption --bucket "$TF_STATE_BUCKET" --profile "$AWS_PROFILE" \
  --server-side-encryption-configuration '{
  "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
}'

# (Optional but recommended) Enforce TLS-only access
aws s3api put-bucket-policy --bucket "$TF_STATE_BUCKET" --profile "$AWS_PROFILE" --policy "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [{
    \"Sid\": \"DenyInsecureTransport\",
    \"Effect\": \"Deny\",
    \"Principal\": \"*\",
    \"Action\": \"s3:*\",
    \"Resource\": [\"arn:aws:s3:::$TF_STATE_BUCKET\",\"arn:aws:s3:::$TF_STATE_BUCKET/*\"],
    \"Condition\": {\"Bool\": {\"aws:SecureTransport\": \"false\"}}
  }]
}"

# Create DynamoDB lock table
echo "Creating DynamoDB table for state locking..."
if aws dynamodb describe-table --table-name "$TF_LOCK_TABLE" --profile "$AWS_PROFILE" 2>/dev/null; then
    echo "✅ DynamoDB table $TF_LOCK_TABLE already exists"
else
    aws dynamodb create-table \
      --table-name "$TF_LOCK_TABLE" \
      --attribute-definitions AttributeName=LockID,AttributeType=S \
      --key-schema AttributeName=LockID,KeyType=HASH \
      --billing-mode PAY_PER_REQUEST \
      --profile "$AWS_PROFILE"
    echo "✅ DynamoDB table $TF_LOCK_TABLE created"
fi

echo ""
echo "✅ Setup completed successfully!"
echo "Bucket: $TF_STATE_BUCKET"
echo "DynamoDB table: $TF_LOCK_TABLE"
echo ""

# Check if terraform directories exist before running init
echo "Configuring Terraform backends..."

# VPC stack (foundation)
if [ -d "terraform/stacks/vpc" ]; then
    echo "Initializing VPC stack..."
    cd terraform/stacks/vpc
    terraform init -reconfigure \
      -backend-config="bucket=$TF_STATE_BUCKET" \
      -backend-config="key=terraform/states/dev/vpc.tfstate" \
      -backend-config="region=$AWS_REGION" \
      -backend-config="dynamodb_table=$TF_LOCK_TABLE" \
      -backend-config="encrypt=true"
    cd - > /dev/null
else
    echo "⚠️  terraform/stacks/vpc directory not found, skipping VPC stack init"
fi

# KMS stack (independent)
if [ -d "terraform/stacks/kms" ]; then
    echo "Initializing KMS stack..."
    cd terraform/stacks/kms
    terraform init -reconfigure \
      -backend-config="bucket=$TF_STATE_BUCKET" \
      -backend-config="key=terraform/states/dev/kms.tfstate" \
      -backend-config="region=$AWS_REGION" \
      -backend-config="dynamodb_table=$TF_LOCK_TABLE" \
      -backend-config="encrypt=true"
    cd - > /dev/null
else
    echo "⚠️  terraform/stacks/kms directory not found, skipping KMS stack init"
fi

# EKS stack (depends on VPC)
if [ -d "terraform/stacks/eks" ]; then
    echo "Initializing EKS stack..."
    cd terraform/stacks/eks
    terraform init -reconfigure \
      -backend-config="bucket=$TF_STATE_BUCKET" \
      -backend-config="key=terraform/states/dev/eks.tfstate" \
      -backend-config="region=$AWS_REGION" \
      -backend-config="dynamodb_table=$TF_LOCK_TABLE" \
      -backend-config="encrypt=true"
    cd - > /dev/null
else
    echo "⚠️  terraform/stacks/eks directory not found, skipping EKS stack init"
fi

# IRSA stack (depends on EKS and KMS)
if [ -d "terraform/stacks/irsa" ]; then
    echo "Initializing IRSA stack..."
    cd terraform/stacks/irsa
    terraform init -reconfigure \
      -backend-config="bucket=$TF_STATE_BUCKET" \
      -backend-config="key=terraform/states/dev/irsa.tfstate" \
      -backend-config="region=$AWS_REGION" \
      -backend-config="dynamodb_table=$TF_LOCK_TABLE" \
      -backend-config="encrypt=true"
    cd - > /dev/null
else
    echo "⚠️  terraform/stacks/irsa directory not found, skipping IRSA stack init"
fi

# ECR stack (independent, optional)
if [ -d "terraform/stacks/ecr" ]; then
    echo "Initializing ECR stack..."
    cd terraform/stacks/ecr
    terraform init -reconfigure \
      -backend-config="bucket=$TF_STATE_BUCKET" \
      -backend-config="key=terraform/states/dev/ecr.tfstate" \
      -backend-config="region=$AWS_REGION" \
      -backend-config="dynamodb_table=$TF_LOCK_TABLE" \
      -backend-config="encrypt=true"
    cd - > /dev/null
else
    echo "⚠️  terraform/stacks/ecr directory not found, skipping ECR stack init"
fi

# Observability stack (depends on EKS, optional)
if [ -d "terraform/stacks/observability" ]; then
    echo "Initializing Observability stack..."
    cd terraform/stacks/observability
    terraform init -reconfigure \
      -backend-config="bucket=$TF_STATE_BUCKET" \
      -backend-config="key=terraform/states/dev/observability.tfstate" \
      -backend-config="region=$AWS_REGION" \
      -backend-config="dynamodb_table=$TF_LOCK_TABLE" \
      -backend-config="encrypt=true"
    cd - > /dev/null
else
    echo "⚠️  terraform/stacks/observability directory not found, skipping Observability stack init"
fi

echo ""
echo "🎉 All done! Your Terraform backend is configured."
echo ""
echo "Next steps for PRODUCTION deployment (stacks-only architecture):"
echo "1. Export your AWS profile: export AWS_PROFILE=$AWS_PROFILE"
echo "2. Export the TF state bucket: export TF_STATE_BUCKET=$TF_STATE_BUCKET"
echo ""
echo "Deploy stacks in dependency order using prod.tfvars:"
echo ""
echo "3. Deploy VPC:"
echo "   cd terraform/stacks/vpc"
echo "   terraform plan -var-file=../../envs/prod/prod.tfvars"
echo "   terraform apply -var-file=../../envs/prod/prod.tfvars"
echo ""
echo "4. Deploy KMS:"
echo "   cd ../kms"
echo "   terraform plan -var-file=../../envs/prod/prod.tfvars"
echo "   terraform apply -var-file=../../envs/prod/prod.tfvars"
echo ""
echo "5. Deploy EKS:"
echo "   cd ../eks"
echo "   terraform plan -var-file=../../envs/prod/prod.tfvars -var=\"tf_state_bucket=\$TF_STATE_BUCKET\""
echo "   terraform apply -var-file=../../envs/prod/prod.tfvars -var=\"tf_state_bucket=\$TF_STATE_BUCKET\""
echo ""
echo "6. Deploy IRSA:"
echo "   cd ../irsa"
echo "   terraform plan -var-file=../../envs/prod/prod.tfvars -var=\"tf_state_bucket=\$TF_STATE_BUCKET\""
echo "   terraform apply -var-file=../../envs/prod/prod.tfvars -var=\"tf_state_bucket=\$TF_STATE_BUCKET\""
echo ""
echo "Backend configuration:"
echo "  Bucket: $TF_STATE_BUCKET"
echo "  Region: $AWS_REGION"
echo "  DynamoDB: $TF_LOCK_TABLE"
echo ""
echo "Infrastructure stacks (with separate state files):"
echo "  📁 terraform/stacks/vpc/       → terraform/states/prod/vpc.tfstate"
echo "  📁 terraform/stacks/kms/       → terraform/states/prod/kms.tfstate"
echo "  📁 terraform/stacks/eks/       → terraform/states/prod/eks.tfstate"
echo "  📁 terraform/stacks/irsa/      → terraform/states/prod/irsa.tfstate"
echo "  📁 terraform/stacks/ecr/       → terraform/states/prod/ecr.tfstate (optional)"
echo "  📁 terraform/stacks/observability/ → terraform/states/prod/observability.tfstate (optional)"
echo ""
echo "Dependencies:"
echo "  VPC ← (none)"
echo "  KMS ← (none)"
echo "  EKS ← VPC (via remote state)"
echo "  IRSA ← EKS + KMS (via remote state)"
echo ""
echo "✅ Using enterprise-level stacks architecture for production deployment!"
echo "⚠️  Deploy stacks in dependency order to avoid errors!"