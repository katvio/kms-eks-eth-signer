# Phase 5 Deployment Guide - Nitro Enclaves with Enclaver

## 🔒 Security Enhancement: Hardware-Level Attestation

This guide enhances your existing Ethereum transaction signer with **AWS Nitro Enclaves** using **Enclaver**. This provides:

- **Hardware-level security** guarantees
- **Cryptographic attestation** ensuring only your specific enclave can access KMS keys
- **Zero-trust architecture** with PCR-based key policies
- **Tamper-evident execution** environment

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        EKS Cluster                              │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                 Nitro Enclave Node                          ││
│  │  ┌─────────────────────────────────────────────────────────┐││
│  │  │              Nitro Enclave                              │││
│  │  │  ┌─────────────────────────────────────────────────────┐│││
│  │  │  │           Go Signer App                             ││││
│  │  │  │  • Ethereum transaction signing                     ││││
│  │  │  │  • KMS integration via Enclaver proxy               ││││
│  │  │  │  • Hardware attestation                             ││││
│  │  │  └─────────────────────────────────────────────────────┘│││
│  │  │  ┌─────────────────────────────────────────────────────┐│││
│  │  │  │           Enclaver Runtime                          ││││
│  │  │  │  • KMS Proxy (localhost:9999)                      ││││
│  │  │  │  • Attestation document generation                  ││││
│  │  │  │  • Network isolation                                ││││
│  │  │  └─────────────────────────────────────────────────────┘│││
│  │  └─────────────────────────────────────────────────────────┘││
│  │                           │                                 ││
│  │                           │ Attested KMS Request             ││
│  │                           ▼                                 ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
    ┌─────────────────────────────────────────────────────────────┐
    │                    AWS KMS                                  │
    │  ┌─────────────────────────────────────────────────────────┐│
    │  │              Ethereum Private Key                       ││
    │  │  • Protected by PCR attestation policy                 ││
    │  │  • Only accessible from verified enclave               ││
    │  │  • Specific image hash (PCR0) required                 ││
    │  │  └─────────────────────────────────────────────────────┘│
    └─────────────────────────────────────────────────────────────┘
```

## Prerequisites

✅ **Completed Phase 4** (Kustomize deployment working)  
✅ **AWS Account** with admin permissions  
✅ **EKS cluster** running  
✅ **Enclaver binary** installed locally  
✅ **Docker** for building enclave images  

## Step 1: Install and Setup Enclaver

### Download Enclaver Binary

```bash
# Download Enclaver for your platform
cd $HOME/pro_wks/kms-eks-eth-signer/enclaver

# For macOS (if not already present)
curl -L https://github.com/edgebitio/enclaver/releases/latest/download/enclaver-darwin-amd64 -o enclaver
chmod +x enclaver

# Verify installation
./enclaver --version
```

## Step 2: Modify Go Application for Nitro Enclaves

The Go application needs to be modified to:
1. Use the Enclaver KMS proxy endpoint
2. Integrate with Nitro Enclaves SDK for attestation
3. Handle enclave-specific networking

### Key Changes Required:
- Add Nitro Enclaves SDK dependency
- Configure KMS client to use Enclaver proxy
- Add attestation document generation
- Update networking configuration

## Step 3: Create Enclaver Manifest

The `enclaver.yaml` file defines how your application runs in the enclave

## Step 4: Update Terraform for Nitro Enclaves

### Add Nitro Enclaves Node Group

The current EKS setup needs a new node group specifically for Nitro Enclaves:

```bash
# 1. Deploy Terraform (Nitro Enclaves node group)
cd terraform/stacks/eks
terraform plan -var-file="../../envs/prod/prod.tfvars"
terraform apply -var-file="../../envs/prod/prod.tfvars"
# 2. Wait for nodes to be ready
kubectl get nodes -l edgebit.io/enclave=nitro
```

### Enhanced KMS Key Policy with PCR Attestation

The KMS key policy needs to be updated to require attestation:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowNitroEnclaveAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT:role/nitro-enclaves-role"
      },
      "Action": [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Sign"
      ],
      "Resource": "*",
      "Condition": {
        "StringEqualsIgnoreCase": {
          "kms:RecipientAttestation:ImageSha384": "da58063e5caf2e4a534a532e363f70319e5f6291e49e20afb1f9219958377dd5d6d1090b525ec32d70fbc785feacbb71"
        }
      }
    }
  ]
}
```

## Step 5: Build and Deploy Enclave Image

### Build the Enclave Image

```bash
export DOCKER_DEFAULT_PLATFORM=linux/amd64

cd $HOME/pro_wks/kms-eks-eth-signer

# Build the Go application image first
docker build --platform linux/amd64 -t eth-go-signer:latest ./go-signer-app
docker image inspect eth-go-signer:latest | grep Architecture

docker buildx create --name multiarch --use || true
docker buildx build --platform linux/amd64 -t eth-go-signer:latest ./go-signer-app --load
# Now build enclave
./enclaver/enclaver build
docker image inspect eth-go-signer:enclave-latest | grep Architecture

# Create a unique tag
export IMAGE_TAG=$(date +%Y%m%d-%H%M%S)
echo "Using tag: $IMAGE_TAG"

# Tag and push with unique tag
docker tag eth-go-signer:latest docker.io/flentier/eth-go-signer:$IMAGE_TAG
docker tag eth-go-signer:enclave-latest docker.io/flentier/eth-go-signer:enclave-$IMAGE_TAG
docker push docker.io/flentier/eth-go-signer:$IMAGE_TAG
docker push docker.io/flentier/eth-go-signer:enclave-$IMAGE_TAG


sed -i "s/enclave-latest/enclave-20250818-175938/g" k8s/overlays/nitro/job-nitro.yaml

---

# This creates: eth-go-signer:enclave-latest
docker tag eth-go-signer:latest docker.io/flentier/eth-go-signer:latest

docker tag eth-go-signer:enclave-latest docker.io/flentier/eth-go-signer:enclave-latest

docker push docker.io/flentier/eth-go-signer:latest
docker push docker.io/flentier/eth-go-signer:enclave-latest

```

### Extract PCR Values

```bash
# Get the PCR measurements for KMS policy
Built Release Image: sha256:63602c6f4dc29f6ca821992d6dbb751c2a6fc8cf2daa2fcfbc897558d4c98162 (eth-go-signer:enclave-latest)
EIF Info:

Built Release Image: sha256:531b4bea6d6132cad82664c885bd57ac434995914f080facee01168b0dfbcd92 (eth-go-signer:enclave-latest)
EIF Info:

{
  "Measurements": {
    "PCR0": "4dd38643d09593282ff1dd930f26b2c4bb9f8396afb647d6235e4228a7c60892397063fb38018121e7a19cb85b573281",
    "PCR1": "3b4a7e1b5f13c5a1000b3ed32ef8995ee13e9876329f9bc72650b918329ef9cf4e2e4d1e1e37375dab0ba56ba0974d03",
    "PCR2": "6e248591c526e3d07331ddaa13525faaa247c9657e2de80dba31cfb344d6fde622bba62e89fe3fc5f008e7e9e8bacd1d"
  }
}

# Output will include PCR0 hash needed for KMS policy
```

## Step 6: Update Kubernetes Manifests

### Nitro Enclaves Job Specification

```bash
# 3. Deploy the enclave workload
cd $HOME/pro_wks/kms-eks-eth-signer
export AGE_SECRET_KEY="$(cat ~/.age/key.txt)"
kustomize build k8s/overlays/nitro | kubectl apply -f -
# 4. Monitor the deployment
kubectl -n signer logs job/nitro-signer -f
```

## Step 7: Security Verification

### Verify Enclave Attestation

```bash
# Deploy the Nitro Enclaves job
kubectl apply -f k8s/overlays/nitro/

# Check enclave status
kubectl -n signer logs job/signer-nitro

# Expected output should include:
# - Enclave initialization success
# - Attestation document generation
# - KMS proxy connection
# - Successful transaction signing
```

### Verify KMS Access Control

```bash
# Test that regular (non-enclave) access is denied
aws kms decrypt \
  --ciphertext-blob fileb://test-encrypted-data \
  --profile platform-admin

# Should fail with access denied due to missing attestation
```

## Step 8: Monitoring and Observability

### CloudTrail Events

Monitor KMS usage with specific enclave attestation:

```bash
# Check CloudTrail for KMS Sign events with attestation
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=Sign \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query 'Events[?contains(CloudTrailEvent, `RecipientAttestation`)]'
```

### Enclave Metrics

```bash
# Check enclave resource usage
kubectl top pods -n signer -l app=signer-nitro

# Check enclave logs for performance metrics
kubectl -n signer logs -l app=signer-nitro --tail=100
```

## Security Benefits Achieved

### 🔐 **Hardware-Level Security**
- Private key operations occur in hardware-isolated enclave
- Memory encryption and protection against privileged access
- Tamper-evident execution environment

### 🎯 **Zero-Trust Access Control**
- KMS key policy enforces specific enclave image hash (PCR0)
- Cryptographic proof of enclave identity required for key access
- No possibility of key access from compromised host OS

### 📊 **Comprehensive Auditability**
- All KMS operations include attestation documents
- CloudTrail logs show exact enclave measurements
- Immutable audit trail of key usage

## Troubleshooting

### Common Issues

1. **Pod Pending - Insufficient hugepages**
   ```bash
   kubectl describe pod <pod-name>
   # Check node hugepages allocation
   kubectl get nodes -o yaml | grep hugepages
   ```

2. **Enclave Build Failures**
   ```bash
   # Check Enclaver logs
   ./enclaver/enclaver build --verbose
   ```

3. **Network Connectivity Issues**
   ```bash
   # Check egress rules in enclaver.yaml
   # Verify KMS endpoints are allowed
   ```

---
