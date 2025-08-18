package main

import (
	"bufio"
	"encoding/hex"
	"fmt"
	"log"
	"os"
	"regexp"
	"strings"

	"github.com/ethereum/go-ethereum/crypto"
)

func main() {
	if len(os.Args) != 2 {
		log.Fatal("Usage: go run derive-address-simple.go <private-key.pem>")
	}

	keyFile := os.Args[1]
	
	// First, extract the private key using openssl command
	fmt.Printf("📖 Reading private key file: %s\n", keyFile)
	
	// Read the file and extract hex using a simple approach
	file, err := os.Open(keyFile)
	if err != nil {
		log.Fatalf("Failed to open file: %v", err)
	}
	defer file.Close()

	var privateKeyHex string
	scanner := bufio.NewScanner(file)
	
	// Look for hex patterns in the PEM file
	hexPattern := regexp.MustCompile(`[0-9a-fA-F]{64}`)
	
	for scanner.Scan() {
		line := scanner.Text()
		if matches := hexPattern.FindAllString(line, -1); len(matches) > 0 {
			for _, match := range matches {
				if len(match) == 64 { // 32 bytes = 64 hex chars
					privateKeyHex = match
					break
				}
			}
		}
	}

	if privateKeyHex == "" {
		// Alternative: use openssl to extract the key
		fmt.Printf("🔧 Extracting private key using openssl...\n")
		
		// This approach requires manual extraction
		fmt.Printf("Run this command to extract the private key:\n")
		fmt.Printf("openssl ec -in %s -text -noout | grep priv -A 3 | tail -n +2 | tr -d '\\n[:space:]:' | sed 's/^00//'\n", keyFile)
		fmt.Printf("\nThen create a file called 'private-key.hex' with just the hex string and run:\n")
		fmt.Printf("go run derive-address-simple.go private-key.hex\n")
		return
	}

	// Remove any potential 00 prefix
	privateKeyHex = strings.TrimPrefix(privateKeyHex, "00")
	
	// Convert hex to bytes
	privateKeyBytes, err := hex.DecodeString(privateKeyHex)
	if err != nil {
		log.Fatalf("Failed to decode private key hex: %v", err)
	}

	// Create private key using go-ethereum
	privateKey, err := crypto.ToECDSA(privateKeyBytes)
	if err != nil {
		log.Fatalf("Failed to create ECDSA key: %v", err)
	}

	// Derive the Ethereum address
	address := crypto.PubkeyToAddress(privateKey.PublicKey)
	
	// Output results
	fmt.Printf("🔑 Private Key Analysis:\n")
	fmt.Printf("Curve: secp256k1 (Ethereum compatible)\n")
	fmt.Printf("Private Key (hex): %s\n", privateKeyHex)
	fmt.Printf("Public Key (hex): %x\n", crypto.FromECDSAPub(&privateKey.PublicKey))
	fmt.Printf("\n")
	fmt.Printf("🎯 Derived Ethereum Address: %s\n", address.Hex())
	fmt.Printf("\n")
	fmt.Printf("📋 Next Steps:\n")
	fmt.Printf("1. 💰 Fund this address with Sepolia ETH: %s\n", address.Hex())
	fmt.Printf("2. 🚰 Visit faucets:\n")
	fmt.Printf("   - https://www.alchemy.com/faucets/ethereum-sepolia\n")
	fmt.Printf("   - https://faucets.chain.link/sepolia\n")
	fmt.Printf("   - https://sepoliafaucet.com/\n")
	fmt.Printf("3. 🔍 Check balance: https://sepolia.etherscan.io/address/%s\n", address.Hex())
	fmt.Printf("\n")
	fmt.Printf("⚠️  IMPORTANT: This is your SENDER address (KMS-derived)\n")
	fmt.Printf("   The transaction will send FROM this address TO your chosen TO_ADDRESS\n")
	
	// Save address to file for later use
	err = os.WriteFile("ethereum-address.txt", []byte(address.Hex()), 0644)
	if err != nil {
		log.Printf("Warning: Could not save address to file: %v", err)
	} else {
		fmt.Printf("\n💾 Address saved to: ethereum-address.txt\n")
	}
} 