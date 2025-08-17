package main

import (
	"context"
	"fmt"
	"log"
	"math/big"
	"os"
	"strconv"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/kms"
	ethkms "github.com/matelang/go-ethereum-aws-kms-tx-signer"
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
	log.Printf("RPC URL: %s", rpcURL[:50]+"...") // Log only first 50 chars for security

	// Initialize AWS KMS client
	cfg, err := config.LoadDefaultConfig(context.Background())
	if err != nil {
		log.Fatalf("unable to load SDK config, %v", err)
	}
	kmsClient := kms.NewFromConfig(cfg)

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
	feeCap := new(big.Int).Mul(gasPrice, big.NewInt(2)) // 2x current gas price
	gasLimit := uint64(21000) // Standard ETH transfer

	log.Printf("Gas parameters - Tip: %s gwei, Fee Cap: %s gwei, Limit: %d", 
		new(big.Int).Div(tipCap, big.NewInt(1e9)),
		new(big.Int).Div(feeCap, big.NewInt(1e9)),
		gasLimit)

	// Create EIP-1559 transaction
	tx := types.NewTx(&types.DynamicFeeTx{
		ChainID:   big.NewInt(chainID),
		Nonce:     nonce,
		To:        common.HexToAddress(toAddr).Ptr(),
		Value:     value,
		Gas:       gasLimit,
		GasTipCap: tipCap,
		GasFeeCap: feeCap,
	})

	log.Printf("Signing transaction with KMS...")
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
}
