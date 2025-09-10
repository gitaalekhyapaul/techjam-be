#!/bin/bash

# Contract Verification Script for TikTok TechJam 2025
# Verifies TK, TKI, and RevenueController contracts on Etherscan

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check required environment variables
if [ -z "$ETHERSCAN_API_KEY" ]; then
    echo -e "${RED}Error: ETHERSCAN_API_KEY environment variable is required${NC}"
    exit 1
fi

if [ -z "$RPC_URL" ]; then
    echo -e "${RED}Error: RPC_URL environment variable is required${NC}"
    exit 1
fi

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

# Function to verify a contract
verify_contract() {
    local contract_name=$1
    local contract_address=$2
    local constructor_args=$3
    local contract_file=$4
    
    print_status "Verifying $contract_name at $contract_address..."
    
    if [ -n "$constructor_args" ]; then
        forge verify-contract \
            --chain-id 84532 \
            --rpc-url "$RPC_URL" \
            --etherscan-api-key "$ETHERSCAN_API_KEY" \
            --constructor-args "$constructor_args" \
            "$contract_address" \
            "$contract_file"
    else
        forge verify-contract \
            --chain-id 84532 \
            --rpc-url "$RPC_URL" \
            --etherscan-api-key "$ETHERSCAN_API_KEY" \
            "$contract_address" \
            "$contract_file"
    fi
    
    if [ $? -eq 0 ]; then
        print_success "$contract_name verified successfully!"
    else
        print_error "Failed to verify $contract_name"
        return 1
    fi
}

# Main verification process
main() {
    print_status "Starting contract verification process..."
    print_status "Chain: Base Sepolia (84532)"
    print_status "RPC URL: $RPC_URL"
    
    # Get contract addresses from user input
    echo
    read -p "Enter TK contract address: " TK_ADDRESS
    read -p "Enter TKI contract address: " TKI_ADDRESS
    read -p "Enter RevenueController contract address: " RC_ADDRESS
    read -p "Enter DelegationManager contract address: " DELEGATION_MANAGER_ADDRESS
    
    # Validate addresses (basic check)
    if [[ ! $TK_ADDRESS =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        print_error "Invalid TK contract address format"
        exit 1
    fi
    
    if [[ ! $TKI_ADDRESS =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        print_error "Invalid TKI contract address format"
        exit 1
    fi
    
    if [[ ! $RC_ADDRESS =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        print_error "Invalid RevenueController contract address format"
        exit 1
    fi
    
    if [[ ! $DELEGATION_MANAGER_ADDRESS =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        print_error "Invalid DelegationManager contract address format"
        exit 1
    fi
    
    echo
    print_status "Contract addresses validated. Starting verification..."
    echo
    
    # Verify TK contract (no constructor args needed)
    print_status "=== Verifying TK Contract ==="
    verify_contract "TK" "$TK_ADDRESS" "" "src/TK.sol:TK"
    echo
    
    # Verify TKI contract (no constructor args needed)
    print_status "=== Verifying TKI Contract ==="
    verify_contract "TKI" "$TKI_ADDRESS" "" "src/TKI.sol:TKI"
    echo
    
    # Verify RevenueController contract (with constructor args)
    print_status "=== Verifying RevenueController Contract ==="
    
    # Encode constructor arguments for RevenueController
    # Constructor: (address _tk, address _tki, address _delegationManager, uint256 _rebateMonthlyBps, uint256 _maxRebateMonthlyBps, uint256 _secondsPerMonth, uint256 _accrualInterval, uint256 _settlementPeriod)
    # Values: (TK_ADDRESS, TKI_ADDRESS, DELEGATION_MANAGER_ADDRESS, 200, 1000, 30, 1, 7)
    
    # Create a temporary file for constructor args
    CONSTRUCTOR_ARGS_FILE=$(mktemp)
    
    # Use cast to encode the constructor arguments
    cast abi-encode "constructor(address,address,address,uint256,uint256,uint256,uint256,uint256)" \
        "$TK_ADDRESS" \
        "$TKI_ADDRESS" \
        "$DELEGATION_MANAGER_ADDRESS" \
        "200" \
        "1000" \
        "30" \
        "1" \
        "7" > "$CONSTRUCTOR_ARGS_FILE"
    
    # Convert to hex and remove 0x prefix for forge verify-contract
    CONSTRUCTOR_ARGS_HEX=$(cat "$CONSTRUCTOR_ARGS_FILE" | sed 's/^0x//')
    
    verify_contract "RevenueController" "$RC_ADDRESS" "$CONSTRUCTOR_ARGS_HEX" "src/RevenueController.sol:RevenueController"
    
    # Clean up
    rm -f "$CONSTRUCTOR_ARGS_FILE"
    
    echo
    print_success "All contracts verified successfully!"
    print_status "You can view the verified contracts on Etherscan:"
    print_status "TK: https://sepolia.basescan.org/address/$TK_ADDRESS"
    print_status "TKI: https://sepolia.basescan.org/address/$TKI_ADDRESS"
    print_status "RevenueController: https://sepolia.basescan.org/address/$RC_ADDRESS"
}

# Run main function
main "$@"
