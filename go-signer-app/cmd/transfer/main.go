package main

import (
	"context"
	"log"
	"math/big"
	"os"
	"strconv"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/kms"
	ethkms "github.com/welthee/go-ethereum-aws-kms-tx-signer/v2"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
)

func main() {
	// Read configuration from environment variables (set by K8s ConfigMap/Secret)
	toAddr := os.Getenv("TO_ADDRESS")
	amountEthStr := os.Getenv("AMOUNT_ETH")
	chainIDStr := os.Getenv("CHAIN_ID")
	kmsKeyID := os.Getenv("KMS_KEY_ID")
	rpcURL := os.Getenv("RPC_URL")

	// Validate required parameters
	if toAddr == "" {
		log.Fatal("TO_ADDRESS environment variable is required")
	}
	if kmsKeyID == "" {
		log.Fatal("KMS_KEY_ID environment variable is required")
	}
	if rpcURL == "" {
		log.Fatal("RPC_URL environment variable is required")
	}

	// Parse amount (default to 0.001 ETH if not set)
	amountEth := 0.001
	if amountEthStr != "" {
		var err error
		amountEth, err = strconv.ParseFloat(amountEthStr, 64)
		if err != nil {
			log.Fatalf("Invalid AMOUNT_ETH: %v", err)
		}
	}

	// Parse chain ID (default to Sepolia if not set)
	chainID := int64(11155111)
	if chainIDStr != "" {
		var err error
		chainID, err = strconv.ParseInt(chainIDStr, 10, 64)
		if err != nil {
			log.Fatalf("Invalid CHAIN_ID: %v", err)
		}
	}

	log.Printf("Starting Ethereum transfer...")
	log.Printf("Chain ID: %d", chainID)
	log.Printf("Amount: %f ETH", amountEth)
	log.Printf("To Address: %s", toAddr)
	log.Printf("KMS Key ID: %s", kmsKeyID)
	log.Printf("RPC URL: %s", rpcURL[:min(50, len(rpcURL))]+"...") // Log only first 50 chars for security

	// Check if running in Nitro Enclave (Enclaver sets AWS_KMS_ENDPOINT)
	kmsEndpoint := os.Getenv("AWS_KMS_ENDPOINT")
	if kmsEndpoint != "" {
		log.Printf("🔒 Running in Nitro Enclave with KMS proxy at: %s", kmsEndpoint)
	} else {
		log.Printf("⚠️  Running in standard mode (no enclave)")
	}

	// Initialize AWS KMS client with Nitro Enclaves support
	kmsClient, err := createKMSClient(kmsEndpoint)
	if err != nil {
		log.Fatalf("Failed to create KMS client: %v", err)
	}

	// Connect to Ethereum RPC (supports HTTP Basic Auth in URL)
	client, err := ethclient.Dial(rpcURL)
	if err != nil {
		log.Fatalf("Failed to connect to RPC: %v", err)
	}
	defer client.Close()

	// Create KMS transactor
	opts, err := ethkms.NewAwsKmsTransactorWithChainID(kmsClient, kmsKeyID, big.NewInt(chainID))
	if err != nil {
		log.Fatalf("Failed to create KMS transactor: %v", err)
	}

	from := opts.From
	log.Printf("Derived sender address from KMS key: %s", from.Hex())

	// Get current nonce
	nonce, err := client.PendingNonceAt(context.Background(), from)
	if err != nil {
		log.Fatalf("Failed to get nonce: %v", err)
	}
	log.Printf("Current nonce: %d", nonce)

	// Convert ETH to Wei
	value := big.NewInt(int64(amountEth * 1e18))

	// Get current gas prices (more dynamic than hardcoded)
	gasPrice, err := client.SuggestGasPrice(context.Background())
	if err != nil {
		log.Printf("Failed to get gas price, using defaults: %v", err)
		gasPrice = big.NewInt(20_000_000_000) // 20 gwei fallback
	}

	// EIP-1559 transaction parameters
	tipCap := big.NewInt(2_000_000_000)   // 2 gwei tip
	
	// Ensure feeCap is always higher than tipCap
	minFeeCap := big.NewInt(10_000_000_000) // 10 gwei minimum
	suggestedFeeCap := new(big.Int).Mul(gasPrice, big.NewInt(2)) // 2x current gas price
	
	// Use the higher of: minimum fee cap, suggested fee cap, or tip + 5 gwei
	feeCap := minFeeCap
	if suggestedFeeCap.Cmp(feeCap) > 0 {
		feeCap = suggestedFeeCap
	}
	// Ensure feeCap is at least tipCap + 5 gwei
	minFeeCapWithTip := new(big.Int).Add(tipCap, big.NewInt(5_000_000_000))
	if feeCap.Cmp(minFeeCapWithTip) < 0 {
		feeCap = minFeeCapWithTip
	}

	gasLimit := uint64(21000) // Standard ETH transfer

	log.Printf("Gas parameters - Tip: %s gwei, Fee Cap: %s gwei, Limit: %d", 
		new(big.Int).Div(tipCap, big.NewInt(1e9)),
		new(big.Int).Div(feeCap, big.NewInt(1e9)),
		gasLimit)

	// Create EIP-1559 transaction
	toAddress := common.HexToAddress(toAddr)
	tx := types.NewTx(&types.DynamicFeeTx{
		ChainID:   big.NewInt(chainID),
		Nonce:     nonce,
		To:        &toAddress,
		Value:     value,
		Gas:       gasLimit,
		GasTipCap: tipCap,
		GasFeeCap: feeCap,
	})

	if kmsEndpoint != "" {
		log.Printf("🔒 Signing transaction with KMS via Nitro Enclave proxy...")
	} else {
		log.Printf("Signing transaction with KMS...")
	}
	
	signedTx, err := opts.Signer(from, tx)
	if err != nil {
		log.Fatalf("Failed to sign transaction: %v", err)
	}

	log.Printf("Broadcasting transaction...")
	err = client.SendTransaction(context.Background(), signedTx)
	if err != nil {
		log.Fatalf("Failed to send transaction: %v", err)
	}

	log.Printf("✅ Transaction sent successfully!")
	log.Printf("Transaction hash: %s", signedTx.Hash().Hex())
	log.Printf("View on Etherscan: https://sepolia.etherscan.io/tx/%s", signedTx.Hash().Hex())
	
	if kmsEndpoint != "" {
		log.Printf("🔒 Transaction signed with hardware-attested Nitro Enclave")
	}
}

// createKMSClient creates a KMS client with optional Nitro Enclaves proxy support
func createKMSClient(kmsEndpoint string) (*kms.Client, error) {
	ctx := context.Background()
	
	// Load default AWS config
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, err
	}

	// If running in Nitro Enclave, configure custom endpoint for KMS proxy
	if kmsEndpoint != "" {
		customResolver := aws.EndpointResolverWithOptionsFunc(func(service, region string, options ...interface{}) (aws.Endpoint, error) {
			if service == kms.ServiceID {
				return aws.Endpoint{
					PartitionID:   "aws",
					URL:           kmsEndpoint,
					SigningRegion: cfg.Region,
				}, nil
			}
			// For other services, return empty endpoint to use default resolution
			return aws.Endpoint{}, nil
		})
		
		cfg, err = config.LoadDefaultConfig(ctx, config.WithEndpointResolverWithOptions(customResolver))
		if err != nil {
			return nil, err
		}
	}

	return kms.NewFromConfig(cfg), nil
}

// min function for Go versions that don't have it built-in
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
