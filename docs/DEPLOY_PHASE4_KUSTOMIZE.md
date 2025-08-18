# Phase 4 Deployment Guide - Kustomize with BYOK KMS

## Prerequisites
✅ Completed Phase 1 (Terraform stacks)  
✅ Completed Phase 2 (Go app built and pushed to Docker Hub)  
✅ Completed Phase 3 (SOPS secrets configured)  
✅ Completed BYOK KMS setup (new KMS key with imported private key)  
✅ EKS cluster is accessible  
✅ SOPS/age key configured  

## Environment Setup
```bash
export AWS_PROFILE="platform-admin"
export AWS_REGION="eu-west-1"
export TF_STATE_BUCKET="eth-signer-challenge-tfstate-1e79bf1bc6454cf390428fb9d65aa84a"

# Set your BYOK KMS key details (from BYOK setup)
export NEW_KEY_ARN="arn:aws:iam::905418421784:role/kms-eks-eth-prod-irsa"
export ETH_ADDRESS="0x168a8b7BB79A6ED7009018732bFc1D59e85f3C56"

# Verify cluster connectivity
kubectl config current-context
kubectl get nodes
```

## Step 1: Update Kubernetes Configurations

### Update ConfigMap with BYOK KMS Key

```bash
cd /Users/cyrb/pro_wks/kms-eks-eth-signer

# Update the ConfigMap with your BYOK KMS key ARN
# Edit k8s/base/configmap.yaml
```

### Update ServiceAccount with New IRSA Role

```bash
# Get the updated IRSA role ARN (after re-applying IRSA stack with new KMS key)
cd terraform/stacks/irsa
export IRSA_ROLE_ARN=$(terraform output -raw role_arn)
echo "IRSA Role ARN: $IRSA_ROLE_ARN"

# Update k8s/base/serviceaccount.yaml with this ARN
```

## Step 2: Verify SOPS Secrets

```bash
cd /Users/cyrb/pro_wks/kms-eks-eth-signer

# Verify age key is available
export AGE_SECRET_KEY="$(cat ~/.age/key.txt)"

# Test SOPS decryption
sops -d k8s/base/secret.rpcurl.yaml
sops -d k8s/base/secret.docker.yaml

# Both should decrypt successfully showing the actual secret values
```

## Step 3: Update Image Tag (Optional)

```bash
# If you want to use a specific image tag instead of 'latest'
# Update k8s/overlays/prod/kustomization.yaml

# Example: Use git commit hash as tag
export IMAGE_TAG=$(git rev-parse --short HEAD)
echo "Using image tag: $IMAGE_TAG"
```

## Step 4: Deploy the Application

### Method A: Deploy with Current Job Name

```bash
cd /Users/cyrb/pro_wks/kms-eks-eth-signer

# Deploy all resources including the Job
export AGE_SECRET_KEY="$(cat ~/.age/key.txt)"
# Backup the encrypted files first
cp k8s/base/secret.rpcurl.yaml k8s/base/secret.rpcurl.yaml.encrypted
cp k8s/base/secret.docker.yaml k8s/base/secret.docker.yaml.encrypted

# Decrypt in place
sops -d -i k8s/base/secret.rpcurl.yaml
sops -d -i k8s/base/secret.docker.yaml

kustomize build k8s/overlays/prod | kubectl apply -f -

# Check deployment status
kubectl -n signer get all
kubectl -n signer get secrets
kubectl -n signer get configmap

# Watch the Job execution
kubectl -n signer logs job/signer -f
```

### Method B: Deploy with Unique Job Name (Recommended)

```bash
# Create a unique job name for each run
export JOB_NAME="signer-$(date +%s)"
echo "Creating job: $JOB_NAME"

# Deploy with unique job name
export AGE_SECRET_KEY="$(cat ~/.age/key.txt)"
kustomize build k8s/overlays/prod \
  | sed "s/name: signer/name: ${JOB_NAME}/" \
  | kubectl apply -f -

# Follow the logs
kubectl -n signer logs job/${JOB_NAME} -f
```

## Step 5: Monitor and Verify

### Check Job Status
```bash
# List all jobs
kubectl -n signer get jobs

# Check specific job details
kubectl -n signer describe job/signer  # or job/${JOB_NAME}

# Check pod logs
kubectl -n signer get pods
kubectl -n signer logs -l job-name=signer  # or job-name=${JOB_NAME}
```

### Expected Log Output
```
Starting Ethereum transfer...
Chain ID: 11155111
Amount: 0.001000 ETH
To Address: 0x742d35Cc6634C0532925a3b8D9C9C0C5c9C9C0C5
KMS Key ID: arn:aws:kms:eu-west-1:905418421784:key/YOUR-BYOK-KEY-ID
RPC URL: https://eth-sepolia.g.alchemy.com/v2/...
Derived sender address from KMS key: 0xYOUR-DERIVED-ADDRESS
Current nonce: 0
Gas parameters - Tip: 2 gwei, Fee Cap: 40 gwei, Limit: 21000
Signing transaction with KMS...
Broadcasting transaction...
✅ Transaction sent successfully!
Transaction hash: 0x1234567890abcdef...
View on Etherscan: https://sepolia.etherscan.io/tx/0x1234567890abcdef...
```

## Step 6: Verify Transaction on Blockchain

```bash
# Extract transaction hash from logs
export TX_HASH=$(kubectl -n signer logs job/signer | grep "Transaction hash:" | awk '{print $3}')
echo "Transaction Hash: $TX_HASH"

# Check transaction status
curl -X POST https://rpc.sepolia.org \
  -H "Content-Type: application/json" \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"method\": \"eth_getTransactionByHash\",
    \"params\": [\"$TX_HASH\"],
    \"id\": 1
  }" | jq .

# View on Etherscan
echo "View transaction: https://sepolia.etherscan.io/tx/$TX_HASH"
```

## Step 7: Verify CloudTrail Audit

```bash
# Check CloudTrail for KMS Sign events
cd /Users/cyrb/pro_wks/kms-eks-eth-signer

# Set your KMS key ARN
export NEW_KEY_ARN="arn:aws:kms:eu-west-1:905418421784:key/9f0d8cbe-4ded-480e-9400-d0cd8802048a"

# Calculate timestamps for macOS (last 30 minutes)
export START_TIME=$(python3 -c "import time; print(int((time.time() - 1800) * 1000))")
export END_TIME=$(python3 -c "import time; print(int(time.time() * 1000))")

# Search CloudTrail events for KMS Sign operations
aws cloudtrail lookup-events \
  --profile platform-admin \
  --region eu-west-1 \
  --lookup-attributes AttributeKey=EventName,AttributeValue=Sign \
  --start-time $(date -v-30M +%s) \
  --end-time $(date +%s) \
  --query 'Events[?contains(CloudTrailEvent, `9f0d8cbe-4ded-480e-9400-d0cd8802048a`)]'
```

## Step 8: Cleanup Job (Optional)

```bash
# delete all jobs
kubectl -n signer delete jobs --all
```

## 🎯 Complete Workflow Commands

Here's the complete sequence for a new transaction:

```bash
# 1. Set environment
export AGE_SECRET_KEY="$(cat ~/.age/key.txt)"
export JOB_NAME="signer-$(date +%s)"

# 2. Deploy and execute
kustomize build k8s/overlays/prod \
  | sed "s/name: signer/name: ${JOB_NAME}/" \
  | sops -d /dev/stdin \
  | kubectl apply -f -

# 3. Monitor
kubectl -n signer logs job/${JOB_NAME} -f

# 4. Get transaction hash
kubectl -n signer logs job/${JOB_NAME} | grep "Transaction hash:"
```
