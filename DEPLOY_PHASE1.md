# Phase 1 Deployment Guide - Terraform Stacks (PRODUCTION)

## Prerequisites
✅ You've already run `terraform/setup.sh` successfully
✅ AWS credentials are configured with `platform-admin` profile  
✅ All Terraform stacks are initialized

## Environment Setup
```bash
# Export the required environment variables
export AWS_PROFILE="platform-admin"
export AWS_REGION="eu-west-1"
export TF_STATE_BUCKET="eth-signer-challenge-tfstate-1e79bf1bc6454cf390428fb9d65aa84a"

# Verify your bucket exists:
aws s3 ls | grep "eth-signer-challenge-tfstate"
```

## ⚠️ CRITICAL: Deploy in Dependency Order

**You MUST deploy stacks in this exact order** because IRSA depends on remote state from EKS and KMS:

## 1. Deploy VPC Stack (Foundation)
```bash
cd terraform/stacks/vpc

# Plan the deployment
terraform plan -var-file=../../envs/prod/prod.tfvars

# Apply the deployment
terraform apply -var-file=../../envs/prod/prod.tfvars

# Verify outputs
terraform output
```

**Expected Outputs:**
- `vpc_id` - VPC identifier
- `private_subnets` - List of private subnet IDs
- `public_subnets` - List of public subnet IDs

## 2. Deploy KMS Stack (Independent)
```bash
cd ../kms

# Plan the deployment
terraform plan -var-file=../../envs/prod/prod.tfvars

# Apply the deployment  
terraform apply -var-file=../../envs/prod/prod.tfvars

# Verify outputs
terraform output
```

**Expected Outputs:**
- `key_arn` - KMS key ARN (needed for IRSA and K8s ConfigMap)
- `alias_name` - `alias/eth-signer-mainnet-prod`

## 3. Deploy EKS Stack (Depends on VPC)
```bash
cd ../eks

# Plan the deployment
terraform plan \
  -var-file=../../envs/prod/prod.tfvars \
  -var="tf_state_bucket=$TF_STATE_BUCKET"

# Apply the deployment
terraform apply \
  -var-file=../../envs/prod/prod.tfvars \
  -var="tf_state_bucket=$TF_STATE_BUCKET"

# Verify outputs
terraform output

# Update kubeconfig
aws eks update-kubeconfig \
  --region $AWS_REGION \
  --name kms-eks-eth-prod \
  --profile $AWS_PROFILE

# Test cluster connectivity
kubectl get nodes
```

**Expected Outputs:**
- `cluster_endpoint` - EKS API server endpoint
- `oidc_provider_arn` - OIDC provider for IRSA
- `cluster_oidc_issuer_url` - OIDC issuer URL

## 4. Deploy IRSA Stack (Depends on EKS + KMS)
```bash
cd ../irsa

# Plan the deployment
terraform plan \
  -var-file=../../envs/prod/prod.tfvars \
  -var="tf_state_bucket=$TF_STATE_BUCKET"

# Apply the deployment
terraform apply \
  -var-file=../../envs/prod/prod.tfvars \
  -var="tf_state_bucket=$TF_STATE_BUCKET"

# Verify outputs
terraform output
```

**Expected Outputs:**
- `role_arn` - IAM role ARN (needed for K8s ServiceAccount annotation)

## 🎯 Values for Kubernetes Manifests

After successful deployment, collect these values for your K8s manifests:

```bash
# Get KMS Key ARN for ConfigMap
cd terraform/stacks/kms
export KMS_KEY_ARN=$(terraform output -raw key_arn)
echo "KMS Key ARN: $KMS_KEY_ARN"

# Get IRSA Role ARN for ServiceAccount
cd ../irsa  
export IRSA_ROLE_ARN=$(terraform output -raw role_arn)
echo "IRSA Role ARN: $IRSA_ROLE_ARN"
```

**Update these files:**
1. `k8s/base/configmap.yaml` - Set `kmsKeyId: "$KMS_KEY_ARN"`
2. `k8s/base/serviceaccount.yaml` - Set annotation `eks.amazonaws.com/role-arn: "$IRSA_ROLE_ARN"`

## 🏗️ Production Configuration

Using `prod.tfvars` gives you:
- **Environment**: `prod`
- **Cluster**: `kms-eks-eth-prod` 
- **KMS Alias**: `alias/eth-signer-mainnet-prod`
- **Namespace**: `eth-signer`
- **ServiceAccount**: `eth-signer-sa`
- **Node Groups**: 2-6 nodes (3 desired) with `t3.medium`
- **VPC Flow Logs**: Enabled for security

## ✅ Verification Checklist

- [ ] VPC stack deployed successfully with 3 AZs
- [ ] KMS stack deployed with `ECC_SECG_P256K1` key  
- [ ] EKS cluster is accessible (`kubectl get nodes` works)
- [ ] IRSA role created with minimal KMS permissions
- [ ] All Terraform outputs captured for K8s configuration

## 🚨 Troubleshooting

### Common Issues:
1. **IRSA fails**: Make sure VPC, KMS, and EKS are deployed first
2. **Remote state not found**: Deploy dependencies in correct order
3. **Missing TF_STATE_BUCKET**: Verify the bucket name is correct
4. **AWS Profile Issues**: Verify `aws sts get-caller-identity --profile platform-admin` works
5. **Region Mismatch**: Ensure all commands use `eu-west-1` region

### Cleanup (if needed):
```bash
# Destroy in reverse order
cd terraform/stacks/irsa && terraform destroy -var-file=../../envs/prod/prod.tfvars -var="tf_state_bucket=$TF_STATE_BUCKET"
cd ../eks && terraform destroy -var-file=../../envs/prod/prod.tfvars -var="tf_state_bucket=$TF_STATE_BUCKET"  
cd ../kms && terraform destroy -var-file=../../envs/prod/prod.tfvars
cd ../vpc && terraform destroy -var-file=../../envs/prod/prod.tfvars
```

## Next Steps
After Phase 1 completion, proceed to:
- Phase 2: Build and push the Go application
- Phase 3: Configure SOPS/age secrets
- Phase 4: Deploy with Kustomize 