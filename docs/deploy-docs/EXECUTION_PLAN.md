# KMS‑EKS Ethereum Signer — **Execution Plan** (Laser‑Focused, Job‑Triggered)

> **Tech stack (locked in):** Go app using `matelang/go-ethereum-aws-kms-tx-signer` • EKS • AWS KMS (`ECC_SECG_P256K1`) • Terraform (multi-stack, multi-tfstate) • Kustomize (no Helm) • SOPS/age for Secrets • Docker Hub • GitHub Actions (minimal CI/CD) • Chainstack RPC • **Trigger via Kubernetes Job (no API)** • No Prom/Grafana (for now)

---

## Goal (one sentence)

Provision an EKS cluster and an AWS KMS **secp256k1** key (BYOK optional), then deploy a **one‑shot Kubernetes Job** that signs and broadcasts an Ethereum **EIP‑1559** transfer on Sepolia using **KMS‑backed signing**, fully automated via multi‑stack Terraform + Kustomize + SOPS, with CI/CD on GitHub and images hosted on Docker Hub.

---

## Repository structure (authoritative)

```
kms-eks-eth-signer/
├── .DS_Store
├── .github/                              # CI/CD Workflows
│   └── workflows/
│       ├── cd.yaml                       # Continuous Deployment
│       └── ci.yaml                       # Continuous Integration
├── .sops.yaml                            # SOPS encryption configuration
├── go-signer-app/                                  # Ethereum Signer Application
│   ├── cmd/
│   │   └── transfer/
│   │       └── main.go                   # Main transfer application
│   ├── Dockerfile                        # Container image definition
│   ├── go.mod                            # Go module dependencies
│   └── pkg/
│       └── ethkms/                       # Ethereum KMS package
├── challenge-instructions.txt            # Challenge requirements
├── docs/                                 # Documentation
│   ├── architecture.md                   # Architecture documentation
│   └── runbook-demo.md                   # Demo runbook
├── k8s/                                  # Kubernetes Manifests
│   ├── base/                             # Base Kustomize configuration
│   │   ├── configmap.yaml                # Application configuration
│   │   ├── job.yaml                      # Kubernetes Job for signer
│   │   ├── kustomization.yaml            # Kustomize base config
│   │   ├── namespace.yaml                # Namespace definition
│   │   ├── secret.docker.yaml            # Docker registry secret
│   │   ├── secret.rpcurl.yaml            # RPC URL secret
│   │   └── serviceaccount.yaml           # Service account with IRSA
│   └── overlays/
│       └── dev/
│           └── kustomization.yaml        # Dev environment overlay
├── misc-commands.txt                     # Useful commands reference
├── README.md                             # Project documentation
├── steps.txt                             # Step-by-step instructions
└── terraform/                            # Infrastructure as Code
    ├── envs/                             # Environment Configurations
    │   ├── dev/
    │   │   └── dev.tfvars                # Development variables
    │   └── prod/
    │       └── prod.tfvars               # 🆕 Production variables
    ├── modules/                          # Reusable Terraform Modules
    │   ├── eks/
    │   │   └── README.md                 # EKS module documentation
    │   ├── iam-irsa/                     # ✅ IAM Roles for Service Accounts
    │   │   ├── main.tf                   # IRSA implementation
    │   │   ├── outputs.tf                # IRSA outputs
    │   │   ├── README.md                 # IRSA documentation
    │   │   └── variables.tf              # IRSA variables
    │   ├── kms-eth-key/                  # ✅ Ethereum secp256k1 KMS Keys
    │   │   ├── main.tf                   # KMS key implementation
    │   │   ├── outputs.tf                # KMS outputs
    │   │   ├── README.md                 # KMS documentation
    │   │   └── variables.tf              # KMS variables
    │   ├── observability/
    │   │   └── README.md                 # Observability module docs
    │   └── vpc/
    │       └── README.md                 # VPC module documentation
    ├── setup.sh                          # 🔧 Backend setup script (updated)
    └── stacks/                           # 🎯 Deployable Infrastructure Stacks
        ├── ecr/                          # Container Registry (optional)
        ├── eks/                          # ✅ EKS Cluster Stack
        │   ├── .terraform.lock.hcl       # Provider lock file
        │   ├── main.tf                   # EKS cluster configuration
        │   ├── outputs.tf                # EKS outputs
        │   └── variables.tf              # EKS variables
        ├── irsa/                         # ✅ IAM Roles for Service Accounts Stack
        │   ├── .terraform.lock.hcl       # Provider lock file
        │   ├── main.tf                   # IRSA configuration
        │   ├── outputs.tf                # IRSA outputs
        │   └── variables.tf              # IRSA variables
        ├── kms/                          # ✅ KMS Ethereum Keys Stack
        │   ├── .terraform.lock.hcl       # Provider lock file
        │   ├── main.tf                   # KMS configuration
        │   ├── outputs.tf                # KMS outputs
        │   └── variables.tf              # KMS variables
        ├── observability/                # Monitoring Stack (optional)
        └── vpc/                          # ✅ VPC Network Stack
            ├── .terraform.lock.hcl       # Provider lock file
            ├── main.tf                   # VPC configuration
            ├── outputs.tf                # VPC outputs
            └── variables.tf              # VPC variables
```

> **Note:** Per your request, this document **does not** include IaC code. It focuses on steps, commands, and decisions.

---

## Architecture (at a glance)

- **Infra (Terraform, split stacks)** — `vpc` → `eks` (IRSA enabled) → `kms` (ECC_SECG_P256K1) → `irsa` role bound to `ServiceAccount` in `signer` namespace. Each stack has its **own tfstate** in S3 with DynamoDB locks.
- **App (Go)** — Uses `matelang/go-ethereum-aws-kms-tx-signer` to sign tx digests with KMS; builds EIP‑1559 transfer; gets nonce/fees via **Chainstack**; broadcasts; prints tx hash.
- **Kubernetes (Kustomize)** — Namespace, IRSA‑annotated ServiceAccount, **Job** (one‑shot), ConfigMap (chainId/amount/kmsKeyId), SOPS‑encrypted Secrets (RPC URL + Docker Hub pull secret).
- **Trigger model (explicit)** — **No API**. You trigger a transfer by **creating a new Job** (unique name) or re‑creating the existing one. This minimizes attack surface and matches the challenge.
- **Security** — Least‑privileged IAM (`kms:Sign`, `kms:GetPublicKey`, `kms:DescribeKey` on the key), IRSA only (no node creds), SOPS/age, private image pulls, CloudTrail auditing.
- **Observability (minimal)** — Container stdout → CloudWatch; CloudTrail for KMS `Sign` audit. (Prom/Grafana intentionally out of scope.)

---

## Phase 0 — Prereqs (once)

1. **Identity & account hygiene**
   - Use an **admin identity** (SSO/IAM) with MFA; avoid root except for initial bootstrap.
2. **Terraform backend (shared)**
   - Create **S3 bucket** (versioned, encrypted) + **DynamoDB lock table** using your admin profile.
   - Use **one bucket** and **distinct keys** per stack:  
     `terraform/states/dev/{vpc,eks,kms,iam-irsa}.tfstate`
3. **Tools (macOS)**
   - Install/upgrade with Homebrew: `awscli`, `terraform`, `kubectl`, `kustomize`, `sops`, `age`, `go`, `jq`, `yq`, `docker`.
4. **age key**
   - `age-keygen -o ~/.age/key.txt` → put **public** key into `.sops.yaml`; store **AGE_SECRET_KEY** in GitHub Secrets.

---

## Phase 1 — Terraform stacks (apply in order)

> Initialize each stack with its **own backend key** and apply with your `dev.tfvars`.

1. **VPC** — create networking (3 AZs, private subnets for nodes, NAT).  
2. **EKS** — create cluster with IRSA enabled; control plane logs → CloudWatch.  
   - `aws eks update-kubeconfig …` → `kubectl get nodes` sanity check.  
3. **KMS** — create `ECC_SECG_P256K1` key + alias (`alias/eth-signer-sepolia`).  
   - **Note:** Asymmetric KMS keys **do not support rotation**; document this.  
4. **IRSA** — create IAM role for `system:serviceaccount:signer:eth-signer` with **only** `kms:Sign`, `kms:GetPublicKey`, `kms:DescribeKey` on the KMS key ARN.

**Plumb outputs into K8s manifests:**
- Put KMS key **ARN** into `k8s/base/configmap.yaml` (`kmsKeyId` field).  
- Put IRSA **role ARN** into `k8s/base/serviceaccount.yaml` annotation `eks.amazonaws.com/role-arn`.

---

## Phase 2 — Build & push the app (Docker Hub)

cd $HOME/pro_wks/kms-eks-eth-signer/app

# Build for x86_64 (AMD64) architecture specifically
docker buildx build --platform linux/amd64 -t docker.io/flentier/eth-go-signer:amd64 .

# Push the new image
docker push docker.io/flentier/eth-go-signer:amd64

3. In Kustomize, set the image reference to the pushed `<tag>`.

---

## Phase 3 — Secrets with SOPS/age

- **RPC URL** (`secret.rpcurl.yaml`) and **Docker pull secret** (`secret.docker.yaml`) live in `k8s/base/` and are **encrypted in‑place** with SOPS (using `.sops.yaml` rules).  
- Commit only the **encrypted** files. Keep `AGE_SECRET_KEY` in your shell while decrypting locally or in GitHub Actions for CD.

---

## Phase 4 — Deploy with Kustomize (Job‑triggered)

1. Fill `k8s/base/configmap.yaml` values:
   - `chainId: "11155111"` (Sepolia)  
   - `amountEth: "0.001"` (demo)  
   - `toAddress: "0xCHANGE_ME"` (your dest)  
   - `kmsKeyId: "<KMS_KEY_ARN_FROM_TERRAFORM>"`
2. Fill `k8s/base/serviceaccount.yaml` annotation with the **IRSA role ARN**.
3. Deploy (decrypt on the fly):
   ```bash
   export AGE_SECRET_KEY="$(cat ~/.age/key.txt)"
   kustomize build k8s/overlays/prod |  kubectl apply -f -
   kubectl -n signer get pods
   ```
4. **Trigger model (no API):**
   - **Create a new Job name each time** (recommended):
     ```bash
     JOB=signer-$(date +%s)
     kustomize build k8s/overlays/prod \
     | sed "s/name: signer/name: ${JOB}/" \
     | kubectl apply -f -

     kubectl -n signer logs job/${JOB} -f
     ```
   - **Or re‑create the same Job** (delete & re‑apply):
     ```bash
     kubectl -n signer delete job/signer --ignore-not-found
     kustomize build k8s/overlays/prod | kubectl apply -f -
     kubectl -n signer logs job/signer -f
     ```

**Expected logs:** derived sender address (from KMS pubkey) and a tx hash after broadcast.

---

## Security checklist (bake into docs)

- [ ] **KMS key** type `ECC_SECG_P256K1` (SIGN_VERIFY). Asymmetric key rotation **not supported** — document.  
- [ ] **Key policy**: no wildcards; admin principals scoped; app access is **via IAM role (IRSA)**, not key policy.  
- [ ] **IRSA** role grants **only** `kms:Sign`, `kms:GetPublicKey`, `kms:DescribeKey` on the specific **key ARN**.  
- [ ] **No static AWS creds** in the pod; **no node role**; IRSA only.  
- [ ] **SOPS/age** for RPC & registry secrets; `AGE_SECRET_KEY` stored only in GitHub Secrets.  
- [ ] **Docker Hub** pulls via `imagePullSecrets`; acknowledge rate limits in docs.  
- [ ] **Pod hardening**: runAsNonRoot; minimal base image.  
- [ ] **CloudTrail** enabled and shows `KMS Sign` for tx timestamps.

---

## Demo runbook (5–7 minutes)

1. **Show Terraform outputs**: cluster name, KMS key ARN, IRSA role ARN.  
2. **Deploy Job**; check logs → see **derived 0x address**.  
3. **Fund** the address from a Sepolia faucet.  
4. **Trigger again** (new Job name) → copy **tx hash**; open in Etherscan (Sepolia).  
5. **CloudTrail**: filter on your KMS key for `Sign` events at the tx timestamp.  
6. **Wrap up**: call out security controls (IRSA, least privilege, SOPS, no API exposure).

---

## Acceptance matrix

- [ ] Each Terraform **stack** applies cleanly with its **own tfstate**.  
- [ ] EKS reachable (`kubectl get nodes`).  
- [ ] ServiceAccount annotated with **IRSA role ARN**; pod assumes it.  
- [ ] App logs **derived address** and **tx hash**; tx **confirmed** on Etherscan (Sepolia).  
- [ ] CloudTrail shows **KMS Sign** for that tx time/key.  
- [ ] `terraform destroy` per stack leaves no dangling resources.

---

## Common pitfalls & fixes

- **Digest vs hashing**: KMS must receive the **Keccak‑256 digest** (`MessageType=DIGEST`); your chosen Go lib implements this correctly.  
- **Asymmetric key rotation**: not available — don’t attempt; document it.  
- **IRSA trust mismatch**: ensure `sub=system:serviceaccount:signer:eth-signer` in the role’s trust and pod SA annotation matches.  
- **Secrets**: commit only **encrypted** YAML (SOPS/age).  
- **Docker Hub throttling**: use an authenticated `regcred` and keep images lean.

---

## Future improvements (for the report)

- Swap Docker Hub → **ECR** (IAM pulls, scanning, replication) or add ECR **pull‑through cache** for base images.  
- Tighten **NetworkPolicy** egress to only Chainstack + AWS endpoints.  
- Add Prom/Grafana later with a tiny exporter.  
- Multi‑region key replication; Bottlerocket/Karpenter for hardening/cost.

