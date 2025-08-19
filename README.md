# KMS EKS Ethereum Signer

A secure Ethereum transaction signer using AWS KMS keys deployed on Amazon EKS. This project demonstrates cloud engineering practices and explores using Nitro Enclaves in EKS (currently work in progress).

A video of a little walktrough and the actual setup in action: [click here](https://www.youtube.com/watch?v=FNgz7aXvbqU).

## What This Project Does

This implementation shows how to:

- Use AWS KMS with secp256k1 keys for Ethereum transaction signing
- Deploy infrastructure using modular Terraform stacks
- Run secure workloads on EKS with proper IAM integration
- Implement zero-trust security patterns
- Explore hardware attestation with Nitro Enclaves (wip)

## High-Level Architecture

1. A AWS EKS Cluster that runs a Go app as a K8S Job 
2. this code create a ETH Tx that aims is a tranfer from walletA to walletB
3. to perform the signature it used a private Key that is stored in AWS KMS
4. Access to KMS is granted thanks to IRSA (service account IAM)

## Getting Started

### What You'll Need

- AWS account with sufficient IAM permissions
- These tools: `aws`, `terraform`, `kubectl`, `kustomize`, `sops`, `age`
- Docker for building images
- Go 1.22+ if you want to build locally

### Quick Setup

```bash
git clone https://github.com/katvio/kms-eks-eth-signer
cd kms-eks-eth-signer

# Setup Terraform backend buckets and initialize all stacks
./terraform/setup.sh
```

### Deploy the Infrastructure

```bash
export AWS_PROFILE="your-user-account-profile"
export TF_STATE_BUCKET="your-terraform-state-bucket"

# Deploy in this order (dependencies matter)
cd terraform/stacks/vpc && terraform apply -var-file=../../envs/prod/prod.tfvars
cd ../kms && terraform apply -var-file=../../envs/prod/prod.tfvars  
cd ../eks && terraform apply -var-file=../../envs/prod/prod.tfvars -var="tf_state_bucket=$TF_STATE_BUCKET"
cd ../irsa && terraform apply -var-file=../../envs/prod/prod.tfvars -var="tf_state_bucket=$TF_STATE_BUCKET"
```

### Configure Kubernetes

```bash
# Update your kubeconfig
aws eks update-kubeconfig --region eu-west-1 --name kms-eks-eth-prod

# Setup secrets (you'll need to edit these with your values first)
export AGE_SECRET_KEY="$(cat ~/.age/key.txt)"
# Edit k8s/base/secret.*.yaml with your RPC URL and Docker credentials, then:
sops -e -i k8s/base/secret.rpcurl.yaml
sops -e -i k8s/base/secret.docker.yaml
```

### Run a Transaction

```bash
# Deploy and run the signer
kustomize build k8s/overlays/prod | kubectl apply -f -

# Watch it work
kubectl -n signer logs job/signer -f
```

## Project Structure

```
kms-eks-eth-signer/
├── cloudformation/                 # CloudFormation templates
│   └── nitro-enclaves-nodegroup.yaml
├── docs/                          # Documentation
│   ├── ARCHITECTURE.md            # System design details
│   ├── SUBMISSION_REPORT.md       # Challenge write-up
│   ├── SUBMISSION_CHECKLIST.md    # Requirements check
│   ├── deploy-docs/               # Step-by-step guides
│   │   ├── DEPLOY_PHASE1.md      # Terraform setup
│   │   ├── DEPLOY_PHASE4_KUSTOMIZE.md # Kubernetes deployment
│   │   ├── DEPLOY_PHASE5_NITRO_ENCLAVES.md # Nitro setup (WIP)
│   │   ├── DEPLOY_BYOK_KMS.md    # Bring your own key
│   │   └── EXECUTION_PLAN.md     # Project plan
│   ├── challenge-instructions.txt # Original requirements
│   └── misc-commands.txt          # Useful commands
├── terraform/                     # Infrastructure code
│   ├── stacks/                   # Deployable units
│   │   ├── vpc/                  # Networking
│   │   ├── kms/                  # Key management
│   │   ├── eks/                  # Kubernetes cluster
│   │   └── irsa/                 # IAM roles
│   ├── modules/                  # Reusable components
│   │   ├── iam-irsa/            # IRSA module
│   │   ├── kms-eth-key/         # KMS key module
│   │   └── eks/, vpc/, observability/ # Other modules
│   ├── envs/                    # Environment configs
│   └── setup.sh                 # Backend setup script
├── go-signer-app/                # The actual signer
│   ├── cmd/transfer/             # Main application
│   ├── pkg/ethkms/              # KMS integration
│   ├── Dockerfile               # Container setup
│   └── transfer                 # Built binary
├── go-address-derivation/        # Address derivation tools
├── k8s/                         # Kubernetes manifests
│   ├── base/                    # Base configuration
│   ├── overlays/                # Environment overlays
│   │   ├── prod/                # Production setup
│   │   ├── nitro/               # Nitro Enclaves (WIP)
│   │   └── dev/                 # Development setup
│   ├── nitro-enclaves-installer.yaml # Nitro setup
│   └── hugepages-setup.yaml     # Memory configuration
├── enclaver/                    # Nitro Enclaves stuff (WIP)
│   ├── enclaver.yaml            # Enclave config
│   ├── enclave.go               # Wrapper application
│   ├── enclaver-official-docs/  # Documentation
│   └── enclaver-info*.txt       # Setup notes
├── scripts/                     # Helper scripts
│   └── deploy-nitro-enclaves.sh
└── temp-eth-keys/               # BYOK key material
```

## Security Features

### Multiple Security Layers

**KMS Integration**
- Hardware-backed private keys using HSM
- secp256k1 curve for Ethereum compatibility
- Support for bringing your own keys (BYOK)
- Minimal IAM permissions

**IRSA (No Static Credentials)**
- Pods get AWS access through Kubernetes service accounts
- Automatic credential rotation
- Only Sign, GetPublicKey, and DescribeKey permissions

**Network Security**
- EKS nodes run in private subnets
- Controlled outbound access through NAT gateways
- VPC Flow Logs for monitoring

**Container Security**
- Distroless base images for minimal attack surface
- Non-root execution

**Advanced: Nitro Enclaves (Work in Progress)**
- Hardware-level isolation
- Cryptographic attestation
- PCR-based KMS policies
- Tamper-evident execution

### Audit Trail

- All KMS operations logged via CloudTrail
- EKS control plane logs enabled
- Structured application logging
- Each transaction creates a unique job for traceability

## Key Design Decisions

### Why Kubernetes Jobs Instead of Deployments?

I chose Jobs because they:
- Reduce attack surface (no persistent API endpoints)
- Provide clear audit trails per transaction
- Simplicity
- Isolate failures

### Why Multi-Stack Terraform?

Breaking infrastructure into independent stacks allows:
- Different teams to own different components
- Independent lifecycle management
- Limited blast radius for changes (one tfstate file per stack)
- Easier testing and validation

### Why SOPS Instead of AWS Secrets Manager?

SOPS works better for GitOps because:
- Secrets are versioned with code
- No per-secret AWS charges
- Works offline during development
- Integrates cleanly with Kustomize

### Why IRSA Instead of Static Credentials?

IRSA provides:
- Automatic credential rotation
- No long-lived secrets in containers
- Clear identity attribution
- Kubernetes-native security

## Documentation

Check the `docs/` directory for detailed guides:

- [System Architecture](docs/ARCHITECTURE.md) - How everything fits together
- [Submission Report](docs/SUBMISSION_REPORT.md) - Challenge approach and lessons learned
- [Deployment Guides](docs/deploy-docs/) - Step-by-step deploy instructions

## Local Development of the Go signer app

```bash
# Build the Go app
cd go-signer-app
go mod tidy
go build -o transfer ./cmd/transfer

# Build Docker image
docker build -t eth-go-signer:latest .
```

## Testing iac setup

```bash
# Validate Terraform
cd terraform/stacks/vpc
terraform plan -var-file=../../envs/prod/prod.tfvars

# Validate Kubernetes manifests
kustomize build k8s/overlays/prod | kubectl apply --dry-run=client -f -
```

## Configuration

### Environment Variables

The go signer application uses these settings (configured via Kubernetes):

- `CHAIN_ID`: Ethereum network (11155111 for Sepolia)
- `AMOUNT_ETH`: How much ETH to transfer
- `TO_ADDRESS`: Where to send the ETH
- `KMS_KEY_ID`: AWS KMS key ARN
- `RPC_URL`: Ethereum RPC endpoint

### Terraform Variables

Configure your infrastructure in `terraform/envs/prod/prod.tfvars`:

```hcl
aws_region = "eu-west-1"
environment = "prod"
cluster_name = "kms-eks-eth-prod"
node_instance_types = ["t3.medium"]
```

## Important Notes

### Nitro Enclaves Status

The Nitro Enclaves integration isn't working yet. I've got the infrastructure code and documentation in place, but getting Nitro Enclaves running as EKS worker nodes with PCR0-based KMS policies is proving more complex than expected. The goal is hardware-attested private key protection, but this remains a work in progress.

### What's Missing for Production

This is a demonstration project. For production use, you'd want to add:

- Comprehensive monitoring (Prometheus/Grafana)
- Complete CI/CD pipelines (for the iac and gitops part, as well as security checks)
- Additional security hardening (network policies, pod security standards, IAM/RBAC, Container image signing, OPA/Kyverno policies, admission controllers, vulnerability scanning, misc supply chain security, Chainloop for attestation along with NitroEnclaves, security git repo (signing etc))
- better iam overall security, use of OIDC for  Githubactions so that terrafrom can assume IAM roles in AWS without the need for long-term access keys
- Zerotrust networking where it is relevant along with the use of an external IdP

## Contributing

This project demonstrates cloud engineering patterns. Key areas that could use work:

1. Getting Nitro Enclaves fully working with EKS
2. Adding comprehensive monitoring
3. Implementing additional security measures as described above
4. Creating better operational runbooks


---

**Quick Links**
- [Architecture Overview](docs/ARCHITECTURE.md)
- [Deployment Guide](docs/deploy-docs/DEPLOY_PHASE1.md)
- [Submission Report](docs/SUBMISSION_REPORT.md)
- [Nitro Enclaves Setup](docs/deploy-docs/DEPLOY_PHASE5_NITRO_ENCLAVES.md)
