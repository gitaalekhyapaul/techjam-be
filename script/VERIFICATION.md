# Contract Verification Scripts

This directory contains scripts to verify the deployed smart contracts on Etherscan (Base Sepolia testnet).

## Contracts to Verify

1. **TK.sol** - Stable token contract
2. **TKI.sol** - Interest-bearing token contract
3. **RevenueController.sol** - Main controller contract

## Prerequisites

- `ETHERSCAN_API_KEY` environment variable set
- `RPC_URL` environment variable set (Base Sepolia RPC)
- Foundry installed (`forge` command available)
- Python 3.6+ (for Python script)

## Available Scripts

### 1. Basic Bash Script (`verify_contracts.sh`)

Simple verification script with manual address input.

```bash
# Make executable
chmod +x verify_contracts.sh

# Run verification
./verify_contracts.sh
```

## Usage

### Environment Setup

```bash
export ETHERSCAN_API_KEY="your_etherscan_api_key"
export RPC_URL="https://sepolia.base.org"  # or your preferred Base Sepolia RPC
```

### Running Verification

1. **Deploy your contracts** using the deployment script
2. **Run one of the verification scripts**:
   - The scripts will try to extract addresses from broadcast files automatically
   - If that fails, you'll be prompted to enter addresses manually
3. **Wait for verification** to complete (may take a few minutes)

### Manual Address Input

If automatic extraction fails, you'll need to provide:

- **TK Contract Address**: The deployed TK token contract
- **TKI Contract Address**: The deployed TKI token contract
- **RevenueController Contract Address**: The main controller contract
- **DelegationManager Contract Address**: The delegation manager contract

## Constructor Arguments

The RevenueController contract requires constructor arguments:

```solidity
constructor(
    address _tk,                    // TK token address
    address _tki,                   // TKI token address
    address _delegationManager,     // DelegationManager address
    uint256 _rebateMonthlyBps,      // 200 (2%)
    uint256 _maxRebateMonthlyBps,   // 1000 (10%)
    uint256 _secondsPerMonth,       // 30
    uint256 _accrualInterval,       // 1
    uint256 _settlementPeriod       // 7
)
```

These are automatically encoded by the scripts.

## Troubleshooting

### Common Issues

1. **"Contract already verified"**: The contract is already verified on Etherscan
2. **"Constructor arguments mismatch"**: Check that the deployed contract used the same constructor arguments
3. **"RPC timeout"**: Try using a different RPC URL
4. **"Invalid address format"**: Ensure addresses are valid Ethereum addresses (0x...)

### Verification Status

You can check if a contract is already verified by visiting:

- https://sepolia.basescan.org/address/YOUR_CONTRACT_ADDRESS

### Retry Logic

The advanced scripts include retry logic. If verification fails:

1. Wait 10 seconds
2. Retry up to 3 times
3. Report final status

## Success Output

When verification succeeds, you'll see:

```
[SUCCESS] All contracts verified successfully!
[INFO] You can view the verified contracts on Etherscan:
[INFO] TK: https://sepolia.basescan.org/address/0x...
[INFO] TKI: https://sepolia.basescan.org/address/0x...
[INFO] RevenueController: https://sepolia.basescan.org/address/0x...
```

## Notes

- Verification can take 1-5 minutes per contract
- Make sure your contracts are deployed and confirmed on-chain before verifying
- The scripts assume you're using Base Sepolia (chain ID 84532)
- For mainnet verification, update the chain ID in the scripts
