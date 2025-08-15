package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"math/big"
	"os"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/kms"
	ethkms "github.com/matelang/go-ethereum-aws-kms-tx-signer"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
)

func main() {
	toAddr := flag.String("to", "", "Destination Ethereum address")
	amountEth := flag.Float64("amount", 0.001, "Amount in ETH")
	chainID := flag.Int64("chain-id", 11155111, "Chain ID (Sepolia=11155111)")
	kmsKeyID := flag.String("kms-key-id", "", "AWS KMS key ID or ARN")
	rpcURL := flag.String("rpc-url", os.Getenv("RPC_URL"), "Ethereum RPC URL")
	flag.Parse()

	if *toAddr == "" || *kmsKeyID == "" || *rpcURL == "" {
		log.Fatal("Missing required parameters.")
	}

	cfg, err := config.LoadDefaultConfig(context.Background())
	if err != nil {
		log.Fatalf("unable to load SDK config, %v", err)
	}
	kmsClient := kms.NewFromConfig(cfg)

	client, err := ethclient.Dial(*rpcURL)
	if err != nil {
		log.Fatalf("Failed to connect to RPC: %v", err)
	}

	opts, err := ethkms.NewAwsKmsTransactorWithChainID(kmsClient, *kmsKeyID, big.NewInt(*chainID))
	if err != nil {
		log.Fatalf("Failed to create KMS transactor: %v", err)
	}

	from := opts.From
	fmt.Printf("From address: %s\n", from.Hex())

	nonce, err := client.PendingNonceAt(context.Background(), from)
	if err != nil {
		log.Fatalf("Failed to get nonce: %v", err)
	}

	value := big.NewInt(int64(*amountEth * 1e18)) // ETH to Wei

	// For demo simplicity: fixed gas params
	tipCap := big.NewInt(1_000_000_000)   // 1 gwei
	feeCap := big.NewInt(30_000_000_000) // 30 gwei
	gasLimit := uint64(21000)

	tx := types.NewTx(&types.DynamicFeeTx{
		ChainID:   big.NewInt(*chainID),
		Nonce:     nonce,
		To:        common.HexToAddress(*toAddr).Ptr(),
		Value:     value,
		Gas:       gasLimit,
		GasTipCap: tipCap,
		GasFeeCap: feeCap,
	})

	signedTx, err := opts.Signer(from, tx)
	if err != nil {
		log.Fatalf("Failed to sign tx: %v", err)
	}

	err = client.SendTransaction(context.Background(), signedTx)
	if err != nil {
		log.Fatalf("Failed to send tx: %v", err)
	}

	fmt.Printf("Sent tx: %s\n", signedTx.Hash().Hex())
}
