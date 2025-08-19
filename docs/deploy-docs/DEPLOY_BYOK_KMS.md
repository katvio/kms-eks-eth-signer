# BYOK KMS Setup Guide - Import Ethereum Private Key to AWS KMS

## Prerequisites
✅ You've completed Phase 1 (Terraform stacks deployed)  
✅ AWS credentials configured with `platform-admin` profile  
✅ OpenSSL installed on your system  
✅ Current working directory: `kms-eks-eth-signer/temp-eth-keys`

## Overview

This guide implements the **Bring Your Own Key (BYOK)** approach as specified in the challenge requirements. We'll:
1. Generate a new Ethereum private key
2. Create a KMS key that accepts external key material
3. Import our private key into AWS KMS
4. Derive the Ethereum address for funding
5. Update Kubernetes configurations

## Environment Setup
```bash
# Export required environment variables
export AWS_PROFILE="platform-admin"
export AWS_REGION="eu-west-1"
export KEY_ALIAS="eth-signer-byok-sepolia"

# Verify AWS credentials
aws sts get-caller-identity --profile $AWS_PROFILE
```

## Step 1: Generate Ethereum Private Key

```bash
# Navigate to temp directory
cd $HOME/pro_wks/kms-eks-eth-signer/temp-eth-keys

# Generate secp256k1 private key (Ethereum compatible)
openssl ecparam -name secp256k1 -genkey -noout -out eth-private-key.pem

# Verify the key was generated
ls -la eth-private-key.pem
cat eth-private-key.pem
```

## Step 2: Create KMS Key for Import (BYOK)

```bash
# Create KMS key that accepts external key material
export KMS_KEY_RESPONSE=$(aws kms create-key \
  --profile $AWS_PROFILE \
  --region $AWS_REGION \
  --key-usage SIGN_VERIFY \
  --key-spec ECC_SECG_P256K1 \
  --origin EXTERNAL \
  --description "BYOK Ethereum signing key for Sepolia testnet - Challenge")

# Extract the Key ID
export NEW_KEY_ID=$(echo $KMS_KEY_RESPONSE | jq -r '.KeyMetadata.KeyId')
echo "New KMS Key ID: $NEW_KEY_ID"

# Create alias for easier reference
aws kms create-alias \
  --profile $AWS_PROFILE \
  --region $AWS_REGION \
  --alias-name "alias/$KEY_ALIAS" \
  --target-key-id $NEW_KEY_ID

# Verify key creation
aws kms describe-key --key-id $NEW_KEY_ID --profile $AWS_PROFILE --region $AWS_REGION
```

**Expected Output:**
- Key State: `PendingImport` (waiting for key material)
- Origin: `EXTERNAL`
- Key Spec: `ECC_SECG_P256K1`

## Step 3: Get Import Parameters

```bash
# Get the wrapping key and import token
export IMPORT_PARAMS=$(aws kms get-parameters-for-import \
  --region $AWS_REGION \
  --profile $AWS_PROFILE \
  --key-id $NEW_KEY_ID \
  --wrapping-algorithm RSAES_OAEP_SHA_256 \
  --wrapping-key-spec RSA_2048 \
  --query '{Key:PublicKey,Token:ImportToken}' \
  --output text)

# Extract and decode the parameters
echo $IMPORT_PARAMS | awk '{print $1}' > PublicKey.b64
echo $IMPORT_PARAMS | awk '{print $2}' > ImportToken.b64

# Decode from Base64 to binary
openssl enc -d -base64 -A -in PublicKey.b64 -out PublicKey.bin
openssl enc -d -base64 -A -in ImportToken.b64 -out ImportToken.bin

# Verify files were created
ls -la *.bin *.b64
```

## Step 4: Prepare Key Material for Import

```bash
# Convert private key to DER format (required for KMS import)
cat eth-private-key.pem | openssl pkcs8 -topk8 -outform der -nocrypt > eth-private-key.der

# Encrypt the private key using the KMS wrapping key
openssl pkeyutl \
  -encrypt \
  -in eth-private-key.der \
  -out EncryptedKeyMaterial.bin \
  -inkey PublicKey.bin \
  -keyform DER \
  -pubin \
  -pkeyopt rsa_padding_mode:oaep \
  -pkeyopt rsa_oaep_md:sha256

# Verify encrypted key material was created
ls -la EncryptedKeyMaterial.bin
```

## Step 5: Import Key Material into KMS

```bash
# Import the encrypted key material
aws kms import-key-material \
  --region $AWS_REGION \
  --profile $AWS_PROFILE \
  --key-id $NEW_KEY_ID \
  --encrypted-key-material fileb://EncryptedKeyMaterial.bin \
  --import-token fileb://ImportToken.bin \
  --expiration-model KEY_MATERIAL_DOES_NOT_EXPIRE

# Verify the key is now enabled
aws kms describe-key --key-id $NEW_KEY_ID --profile $AWS_PROFILE --region $AWS_REGION
```

**Expected Output:**
- Key State: `Enabled` (no longer `PendingImport`)
- Origin: `EXTERNAL`

## Step 6: Derive Ethereum Address

```bash
# Extract key details in readable format
cat eth-private-key.pem | openssl ec -text -noout > key-details.txt

# Extract public key (remove 04 prefix for Ethereum)
cat key-details.txt | grep pub -A 5 | tail -n +2 | tr -d '\n[:space:]:' | sed 's/^04//' > public-key-hex.txt

# Extract private key (remove leading 00 if present)
cat key-details.txt | grep priv -A 3 | tail -n +2 | tr -d '\n[:space:]:' | sed 's/^00//' > private-key-hex.txt

echo "Public Key (hex):"
cat public-key-hex.txt
echo ""
echo "Private Key (hex):"
cat private-key-hex.txt
```

## Step 7: Calculate Ethereum Address (Using Go)

```bash
# Copy the address derivation script to temp directory
cp ../derive-address.go .

# Initialize Go module for the derivation script
go mod init address-derivation
go mod tidy

# Run the address derivation script
go run derive-address.go eth-private-key.pem

# The script will output:
# - Private key details
# - Derived Ethereum address
# - Next steps for funding

# Export the derived address for later use
export ETH_ADDRESS=$(cat ethereum-address.txt)
echo "🎯 Your KMS-derived Ethereum address: $ETH_ADDRESS"
echo "👆 This is the address you need to FUND with Sepolia ETH!"
```

## Step 8: Update Terraform KMS Configuration

Now we need to update your Terraform to use the new BYOK key:

```bash
# Get the new key ARN
export NEW_KEY_ARN=$(aws kms describe-key --key-id $NEW_KEY_ID --profile $AWS_PROFILE --region $AWS_REGION --query 'KeyMetadata.Arn' --output text)
echo "New KMS Key ARN: $NEW_KEY_ARN"

# Update the KMS stack to reference the new key
cd $HOME/pro_wks/kms-eks-eth-signer/terraform/stacks/kms

# You'll need to either:
# Option A: Update the KMS module to output the BYOK key ARN
# Option B: Manually update the Kubernetes configs with the new ARN
```

## Step 9: Update Kubernetes Configuration

```bash
# Navigate back to project root
cd $HOME/pro_wks/kms-eks-eth-signer

# Update ConfigMap with new KMS key ARN
# (This will be done via file editing)
```

## Step 10: Fund the Derived Address

```bash
echo "🎯 IMPORTANT: Fund this address with Sepolia ETH:"
echo "Address: $ETH_ADDRESS"
echo ""
echo "Get Sepolia ETH from faucets:"
echo "- https://sepoliafaucet.com/"
echo "- https://www.alchemy.com/faucets/ethereum-sepolia"
echo "- https://faucets.chain.link/sepolia"
echo ""
echo "You need at least 0.01 SepoliaETH for gas + transfer amount"
```

## Step 11: Update IRSA Permissions

The IRSA role needs to be updated to use the new KMS key:

```bash
# Update IRSA stack with new key ARN
cd terraform/stacks/irsa

# Re-apply with the new key ARN
terraform plan \
  -var-file=../../envs/prod/prod.tfvars \
  -var="tf_state_bucket=$TF_STATE_BUCKET" \
  -var="kms_key_arn=$NEW_KEY_ARN"

terraform apply \
  -var-file=../../envs/prod/prod.tfvars \
  -var="tf_state_bucket=$TF_STATE_BUCKET" \
  -var="kms_key_arn=$NEW_KEY_ARN"
```

## Step 12: Test the BYOK Key

```bash
# Test that the key can be used for signing
aws kms get-public-key \
  --key-id $NEW_KEY_ID \
  --profile $AWS_PROFILE \
  --region $AWS_REGION

# The public key should match what you derived locally
```

## ⚠️ Security Notes

1. **Private Key Storage**: The private key files in `temp-eth-keys/` contain sensitive material
2. **Cleanup**: After successful import, securely delete local private key files
3. **Backup**: Consider securely backing up the private key before deletion
4. **Access**: Only import keys you fully control and trust

## 🎯 Values for Kubernetes

After successful BYOK setup:

```bash
# New values for your manifests:
echo "KMS Key ARN (for ConfigMap): $NEW_KEY_ARN"
echo "Ethereum Address (to fund): $ETH_ADDRESS"
echo "TO_ADDRESS (recipient): [Your choice - any valid Ethereum address]"
```

## Cleanup After Success

```bash
# ⚠️ ONLY run after successful KMS import and testing
cd $HOME/pro_wks/kms-eks-eth-signer
rm -rf temp-eth-keys/

# Or securely backup first:
# tar -czf eth-key-backup-$(date +%Y%m%d).tar.gz temp-eth-keys/
# gpg -c eth-key-backup-$(date +%Y%m%d).tar.gz
# rm eth-key-backup-$(date +%Y%m%d).tar.gz
# rm -rf temp-eth-keys/
```

### Verification Commands:

```bash
# Check key state
aws kms describe-key --key-id $NEW_KEY_ID --profile $AWS_PROFILE

# Test signing capability (this should work after import)
echo "test message" | aws kms sign \
  --key-id $NEW_KEY_ID \
  --message-type RAW \
  --signing-algorithm ECDSA_SHA_256 \
  --profile $AWS_PROFILE \
  --region $AWS_REGION
```

## Next Steps

After completing BYOK setup:
1. Update `k8s/base/configmap.yaml` with new KMS key ARN
2. Update `k8s/base/serviceaccount.yaml` with updated IRSA role ARN  
3. Fund the derived Ethereum address with Sepolia ETH
4. Proceed with Phase 4 Kustomize deployment
5. Test the complete transaction flow

---
