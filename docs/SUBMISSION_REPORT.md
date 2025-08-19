# Zama Challenge Submission Report

**Project**: Secure Ethereum Transaction Signer on AWS EKS with KMS  

**Author**: Cyril B

**Date**: 19 aug 25

## Overview

This repo contains a secure Ethereum transaction signer using AWS KMS keys deployed on Amazon EKS. The project demonstrates cloud engineering practices and explores some advanced security concepts, particularly around Nitro Enclaves (wip).

The main goal was to show how we can use AWS's HSMs to sign Ethereum transactions in a secure, auditable way while running everything on Kubernetes.
The current overall security setup is not suitable for prod usage because it lacks a lot of cloud native security good practices and more (see bellow).

## My Approach

### Why I Chose This Architecture

**Multi-Stack Terraform**: Instead of throwing everything into one giant Terraform configuration, I split it into independent stacks - VPC, KMS, EKS, and IRSA.

**Kubernetes Jobs Instead of Services**: Rather than running a persistent service that's always listening for requests, I used Kubernetes Jobs that spin up for this demo, do their work, and die. This significantly reduces the attack surface since there's no API sitting around waiting to be compromised. Each transaction gets its own job, which creates a nice audit trail. This is OFC not suitable for prod use since in terms of response times it is not fast enough because of the K8S's time to spawn the job.

**IRSA for AWS Access**: No static AWS credentials anywhere. The Kubernetes service accounts automatically get temporary AWS credentials through IAM roles.

### Security Philosophy

1. **Network isolation** - EKS nodes live in private subnets
2. **Identity federation** - IRSA handles AWS access securely
3. **Secret management** - Everything encrypted with SOPS/age
4. **Minimal permissions** - The application can only sign with one specific KMS key
5. **Comprehensive auditing** - CloudTrail logs every KMS operation

But many things should be improved in terms of security:

- Additional security hardening (network policies, pod security standards, IAM/RBAC, Container image signing, OPA/Kyverno policies, admission controllers, vulnerability scanning, misc supply chain security, Chainloop for attestation along with NitroEnclaves, security git repo (signing etc))
better iam overall security, use of OIDC for Githubactions so that terrafrom can assume IAM roles in AWS without the need for long-term access keys. External IdP, Yubikeys for the superadmin AWS account, etc
- The use of nitro enclaves in EKS


## Challenges and Lessons Learned

### The Nitro Enclaves Rabbit Hole

This was the big challenge that didn't quite pan out. I spent a lot of time trying to get Nitro Enclaves working as EKS worker nodes. The idea was to have hardware-attested execution where the KMS key could only be accessed from within a cryptographically verified enclave.

**What I tried:**

- Custom EKS node groups with Nitro Enclaves support
- DaemonSets to automatically install the Nitro CLI
- Hugepages configuration for enclave memory
- Integration with [Enclaver](https://github.com/enclaver-io/enclaver) (a third-party tool that simplifies enclave deployment)

**What I learned:**

The documentation for running Nitro Enclaves on EKS is pretty sparse. Most examples assume you're running on plain EC2 instances. which is something i've done in the past for [this project](https://github.com/katvio/acra-enclave).
The resource requirements (hugepages, CPU allocation) add significant operational complexity.

I know it is possible, just have to spend a bit o$more time on it. I find this part really interesting and exciting.

Enven though there is a limitation:
*"Due to Amazon restrictions, each EC2 machine can only run a single enclave at a time. This is enforced by topologySpreadConstraints in the Deployment."*

-> I will try using [Anjura.io](https://docs.anjuna.io/latest/nitro/latest/getting_started/kubernetes_tools/nitro_eks_overview.html) instead of of the Enclaver tool.


## What I'd Do Next

If I were continuing this project:

1. **Fix the Nitro Enclaves integration** - This is the most interesting technical challenge remaining
2. **Add comprehensive monitoring** - Prometheus/Grafana with custom metrics for the signing operations
3. **Implement full CI/CD** - GitOps workflows with automated testing and deployment
4. **Multi-region deployment** - Cross-region KMS key replication and failover
5. **Performance optimization** - Transaction batching, use of API in Go code instead of a K8S Job, etc.
6. **Security improvements** - See list above
7. I would explore the deployment of MPC nodes in this Infra setup, as i've done in [this MPC signing project ](https://mpc-signing.katvio.com/). Would love to explore if that would be relevant to store the key shards into KMS HSM.

## Final Thoughts

While the Nitro Enclaves piece didn't come together completely, I'm pretty happy with what I built. The infrastructure is solid, the security model is sound, and the documentation should make it easy for someone else to pick up and extend.

The focus on building the right foundation rather than implementing every possible feature reflects how I approach real-world engineering problems. Sometimes it's better to do fewer things really well than to try to check every box.

This project represents the kind of infrastructure foundation you could build a production system on, with clear paths for the enhancements that would be needed for full production use.

## Note: AI-Assisted Development

This project was developed with assistance from AI tools to accelerate development and improve quality:

- **Cursor IDE with Claude 4 Sonnet MAX**: Primary development assistant for debugging Infrastructure as Code, Kubernetes configurations, getting to know CLI commands faster, and writing documentation
- **GPT-5 or O3**: Additional assistance for complex problem-solving, architectural decisions, and code optimization

It assisted me especially for: Rapid prototyping, Debugging typos, writting bash scripts, searching through a lot of Docs

---

**Repository**: https://github.com/katvio/kms-eks-eth-signer  
**Documentation**: Check the `docs/` directory for detailed setup guides  
**Architecture Details**: See `docs/ARCHITECTURE.md` for technical specifications 