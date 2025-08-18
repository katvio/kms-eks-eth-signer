package main

import (
	"crypto/ecdsa"
	"encoding/asn1"
	"encoding/pem"
	"fmt"
	"io/ioutil"
	"log"
	"math/big"
	"os"

	"github.com/ethereum/go-ethereum/crypto"
)

// ASN.1 structure for EC private key
type ecPrivateKey struct {
	Version       int
	PrivateKey    []byte
	NamedCurveOID asn1.ObjectIdentifier `asn1:"optional,explicit,tag:0"`
	PublicKey     asn1.BitString        `asn1:"optional,explicit,tag:1"`
}

func main() {
	if len(os.Args) != 2 {
		log.Fatal("Usage: go run derive-address.go <private-key.pem>")
	}

	keyFile := os.Args[1]
	
	// Read the PEM file
	pemData, err := ioutil.ReadFile(keyFile)
	if err != nil {
		log.Fatalf("Failed to read private key file: %v", err)
	}

	// Decode PEM block
	block, _ := pem.Decode(pemData)
	if block == nil {
		log.Fatal("Failed to decode PEM block")
	}

	// Parse the ASN.1 structure
	var privKey ecPrivateKey
	_, err = asn1.Unmarshal(block.Bytes, &privKey)
	if err != nil {
		log.Fatalf("Failed to parse ASN.1 structure: %v", err)
	}

	// Create ECDSA private key from the raw bytes
	privateKeyInt := new(big.Int).SetBytes(privKey.PrivateKey)
	privateKey := &ecdsa.PrivateKey{
		PublicKey: ecdsa.PublicKey{
			Curve: crypto.S256(), // secp256k1
		},
		D: privateKeyInt,
	}
	
	// Calculate public key
	privateKey.PublicKey.X, privateKey.PublicKey.Y = privateKey.PublicKey.Curve.ScalarBaseMult(privKey.PrivateKey)

	// Derive the Ethereum address using go-ethereum
	address := crypto.PubkeyToAddress(privateKey.PublicKey)
	
	// Output results
	fmt.Printf("🔑 Private Key Analysis:\n")
	fmt.Printf("Curve: secp256k1 (Ethereum compatible)\n")
	fmt.Printf("Private Key (hex): %x\n", privKey.PrivateKey)
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
	err = ioutil.WriteFile("ethereum-address.txt", []byte(address.Hex()), 0644)
	if err != nil {
		log.Printf("Warning: Could not save address to file: %v", err)
	} else {
		fmt.Printf("\n💾 Address saved to: ethereum-address.txt\n")
	}
} 