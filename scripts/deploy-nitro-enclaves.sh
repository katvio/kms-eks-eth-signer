#!/bin/bash

# Nitro Enclaves Deployment Script for KMS Ethereum Signer
# This script automates the deployment of the Ethereum signer with Nitro Enclaves

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOCKER_REGISTRY="${DOCKER_REGISTRY:-cyrbthomas}"
IMAGE_NAME="eth-go-signer"
ENCLAVE_TAG="enclave-latest"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    for tool in docker kubectl terraform aws enclaver; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_error "Please install missing tools and try again."
        exit 1
    fi
    
    # Check Enclaver version
    if ! ./enclaver/enclaver --version &> /dev/null; then
        print_error "Enclaver binary not found or not executable"
        print_error "Please ensure enclaver binary is in ./enclaver/ directory"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured"
        print_error "Please configure AWS credentials and try again"
        exit 1
    fi
    
    # Check kubectl context
    if ! kubectl config current-context &> /dev/null; then
        print_error "kubectl not configured or no active context"
        print_error "Please configure kubectl to connect to your EKS cluster"
        exit 1
    fi
    
    print_success "All prerequisites met"
}

# Function to build the base Docker image
build_base_image() {
    print_status "Building base Docker image..."
    
    cd "$PROJECT_ROOT/go-signer-app"
    
    docker build -t "${IMAGE_NAME}:latest" .
    
    print_success "Base Docker image built: ${IMAGE_NAME}:latest"
}

# Function to build the enclave image
build_enclave_image() {
    print_status "Building Nitro Enclave image..."
    
    cd "$PROJECT_ROOT"
    
    # Build enclave image using Enclaver
    ./enclaver/enclaver build
    
    print_success "Enclave image built: ${IMAGE_NAME}:${ENCLAVE_TAG}"
}

# Function to extract PCR measurements
extract_pcr_measurements() {
    print_status "Extracting PCR measurements..."
    
    cd "$PROJECT_ROOT"
    
    # Get PCR measurements
    local pcr_output
    pcr_output=$(./enclaver/enclaver describe "${IMAGE_NAME}:${ENCLAVE_TAG}" 2>/dev/null || true)
    
    if [ -z "$pcr_output" ]; then
        print_error "Failed to extract PCR measurements"
        print_error "Make sure the enclave image was built successfully"
        exit 1
    fi
    
    # Extract PCR0 (image hash)
    local pcr0_hash
    pcr0_hash=$(echo "$pcr_output" | grep -i "pcr0" | awk '{print $2}' || true)
    
    if [ -z "$pcr0_hash" ]; then
        print_error "Could not extract PCR0 hash from enclave description"
        exit 1
    fi
    
    echo "$pcr0_hash" > "$PROJECT_ROOT/.pcr0_hash"
    print_success "PCR0 hash extracted: $pcr0_hash"
    
    # Display full measurements for reference
    echo "=== Enclave Measurements ==="
    echo "$pcr_output"
    echo "=========================="
}

# Function to push images to registry
push_images() {
    print_status "Pushing images to registry..."
    
    # Tag and push base image
    docker tag "${IMAGE_NAME}:latest" "${DOCKER_REGISTRY}/${IMAGE_NAME}:latest"
    docker push "${DOCKER_REGISTRY}/${IMAGE_NAME}:latest"
    
    # Tag and push enclave image
    docker tag "${IMAGE_NAME}:${ENCLAVE_TAG}" "${DOCKER_REGISTRY}/${IMAGE_NAME}:${ENCLAVE_TAG}"
    docker push "${DOCKER_REGISTRY}/${IMAGE_NAME}:${ENCLAVE_TAG}"
    
    print_success "Images pushed to registry"
}

# Function to update terraform configuration
update_terraform() {
    print_status "Updating Terraform configuration..."
    
    cd "$PROJECT_ROOT/terraform/stacks/eks"
    
    # Apply EKS changes to add Nitro Enclaves node group
    terraform init
    terraform plan -var-file="../../envs/prod/prod.tfvars"
    
    print_warning "Review the Terraform plan above"
    read -p "Do you want to apply these changes? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        terraform apply -var-file="../../envs/prod/prod.tfvars" -auto-approve
        print_success "Terraform changes applied"
    else
        print_warning "Terraform changes skipped"
        return 1
    fi
}

# Function to wait for nodes to be ready
wait_for_nodes() {
    print_status "Waiting for Nitro Enclaves nodes to be ready..."
    
    local max_wait=600  # 10 minutes
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        local nitro_nodes
        nitro_nodes=$(kubectl get nodes -l edgebit.io/enclave=nitro --no-headers 2>/dev/null | wc -l || echo "0")
        
        if [ "$nitro_nodes" -gt 0 ]; then
            local ready_nodes
            ready_nodes=$(kubectl get nodes -l edgebit.io/enclave=nitro --no-headers | grep -c " Ready " || echo "0")
            
            if [ "$ready_nodes" -gt 0 ]; then
                print_success "Nitro Enclaves nodes are ready ($ready_nodes/$nitro_nodes)"
                return 0
            fi
        fi
        
        print_status "Waiting for Nitro Enclaves nodes... ($wait_time/$max_wait seconds)"
        sleep 30
        wait_time=$((wait_time + 30))
    done
    
    print_error "Timeout waiting for Nitro Enclaves nodes to be ready"
    return 1
}

# Function to deploy the enclave workload
deploy_enclave() {
    print_status "Deploying Nitro Enclaves workload..."
    
    cd "$PROJECT_ROOT"
    
    # Ensure SOPS secrets are decrypted
    export AGE_SECRET_KEY="$(cat ~/.age/key.txt)"
    
    # Backup encrypted files
    cp k8s/base/secret.rpcurl.yaml k8s/base/secret.rpcurl.yaml.backup
    cp k8s/base/secret.docker.yaml k8s/base/secret.docker.yaml.backup
    
    # Decrypt secrets
    sops -d -i k8s/base/secret.rpcurl.yaml
    sops -d -i k8s/base/secret.docker.yaml
    
    # Deploy using Kustomize
    kustomize build k8s/overlays/nitro | kubectl apply -f -
    
    # Restore encrypted files
    mv k8s/base/secret.rpcurl.yaml.backup k8s/base/secret.rpcurl.yaml
    mv k8s/base/secret.docker.yaml.backup k8s/base/secret.docker.yaml
    
    print_success "Nitro Enclaves workload deployed"
}

# Function to monitor deployment
monitor_deployment() {
    print_status "Monitoring deployment..."
    
    local job_name="nitro-signer"
    local namespace="signer"
    
    # Wait for job to start
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        if kubectl get job "$job_name" -n "$namespace" &>/dev/null; then
            break
        fi
        
        print_status "Waiting for job to be created... ($wait_time/$max_wait seconds)"
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    if [ $wait_time -ge $max_wait ]; then
        print_error "Job was not created within timeout"
        return 1
    fi
    
    # Follow job logs
    print_status "Following job logs..."
    kubectl logs -f "job/$job_name" -n "$namespace" || true
    
    # Check job status
    local job_status
    job_status=$(kubectl get job "$job_name" -n "$namespace" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")
    
    if [ "$job_status" = "Complete" ]; then
        print_success "Job completed successfully!"
        return 0
    else
        print_error "Job did not complete successfully. Status: $job_status"
        return 1
    fi
}

# Function to verify attestation
verify_attestation() {
    print_status "Verifying Nitro Enclaves attestation..."
    
    # Check CloudTrail for KMS operations with attestation
    local start_time
    start_time=$(date -d '1 hour ago' +%s)
    local end_time
    end_time=$(date +%s)
    
    local events
    events=$(aws cloudtrail lookup-events \
        --lookup-attributes AttributeKey=EventName,AttributeValue=Sign \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --query 'Events[?contains(CloudTrailEvent, `RecipientAttestation`)]' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$events" ]; then
        print_success "Found KMS operations with Nitro Enclaves attestation in CloudTrail"
    else
        print_warning "No attested KMS operations found in CloudTrail (this may be normal for recent deployments)"
    fi
}

# Function to display summary
display_summary() {
    print_success "=== Nitro Enclaves Deployment Complete ==="
    echo
    echo "🔒 Security Features Enabled:"
    echo "  ✅ Hardware-level isolation with Nitro Enclaves"
    echo "  ✅ Cryptographic attestation for KMS access"
    echo "  ✅ PCR-based key policy enforcement"
    echo "  ✅ Tamper-evident execution environment"
    echo
    echo "📊 Deployment Details:"
    echo "  • Docker Registry: ${DOCKER_REGISTRY}"
    echo "  • Enclave Image: ${DOCKER_REGISTRY}/${IMAGE_NAME}:${ENCLAVE_TAG}"
    echo "  • PCR0 Hash: $(cat "$PROJECT_ROOT/.pcr0_hash" 2>/dev/null || echo "Not available")"
    echo "  • Kubernetes Namespace: signer"
    echo
    echo "🔍 Monitoring Commands:"
    echo "  kubectl -n signer get pods"
    echo "  kubectl -n signer logs -l app=signer"
    echo "  kubectl -n signer describe job/nitro-signer"
    echo
    echo "🎉 Your Ethereum signer is now running with maximum security!"
}

# Main deployment function
main() {
    print_status "Starting Nitro Enclaves deployment for KMS Ethereum Signer"
    echo
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Run deployment steps
    check_prerequisites
    build_base_image
    build_enclave_image
    extract_pcr_measurements
    
    # Ask user if they want to push images
    read -p "Push images to registry? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        push_images
    else
        print_warning "Images not pushed to registry. You'll need to push them manually."
    fi
    
    # Ask user if they want to update Terraform
    read -p "Update Terraform to add Nitro Enclaves node group? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if update_terraform; then
            wait_for_nodes
        else
            print_error "Terraform update failed or was skipped"
            exit 1
        fi
    else
        print_warning "Terraform update skipped. Ensure Nitro Enclaves nodes are available."
    fi
    
    # Deploy the enclave
    deploy_enclave
    monitor_deployment
    verify_attestation
    
    display_summary
}

# Run main function
main "$@" 