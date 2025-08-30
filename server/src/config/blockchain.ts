import { createPublicClient, createWalletClient, http, parseEther, getContract } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { localhost } from 'viem/chains';
import { logger } from '../utils/logger';

// Contract ABIs (simplified for this example)
const TK_ABI = [
  { inputs: [{ name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], name: 'mint', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'from', type: 'address' }, { name: 'amount', type: 'uint256' }], name: 'controllerBurn', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'account', type: 'address' }], name: 'balanceOf', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' }
] as const;

const TKI_ABI = [
  { inputs: [{ name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], name: 'mint', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'from', type: 'address' }, { name: 'amount', type: 'uint256' }], name: 'controllerBurn', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'account', type: 'address' }], name: 'balanceOf', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'account', type: 'address' }, { name: 't', type: 'uint8' }], name: 'setActorType', outputs: [], stateMutability: 'nonpayable', type: 'function' }
] as const;

const REVENUE_CONTROLLER_ABI = [
  { inputs: [{ name: 'creator', type: 'address' }, { name: 'tkiAmount', type: 'uint256' }, { name: 'delegation', type: 'bytes' }], name: 'submitClap', outputs: [{ name: 'id', type: 'uint256' }], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'creator', type: 'address' }, { name: 'tkAmount', type: 'uint256' }, { name: 'delegation', type: 'bytes' }], name: 'submitGift', outputs: [{ name: 'id', type: 'uint256' }], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], name: 'mintTK', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'ids', type: 'uint256[]' }, { name: 'flags', type: 'bool[]' }], name: 'approveIntents', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'intentIds', type: 'uint256[]' }, { name: 'creators', type: 'address[]' }], name: 'settleEpoch', outputs: [], stateMutability: 'nonpayable', type: 'function' }
] as const;

export class BlockchainService {
  private publicClient;
  private walletClient;
  private account;
  private tkContract;
  private tkiContract;
  private revenueControllerContract;

  constructor() {
    const rpcUrl = process.env.RPC_URL || 'http://localhost:8545';
    const privateKey = process.env.PRIVATE_KEY;
    const chainId = parseInt(process.env.CHAIN_ID || '31337');

    if (!privateKey) {
      throw new Error('PRIVATE_KEY environment variable is not set');
    }

    this.publicClient = createPublicClient({
      chain: localhost,
      transport: http(rpcUrl),
    });

    this.account = privateKeyToAccount(privateKey as `0x${string}`);
    
    this.walletClient = createWalletClient({
      account: this.account,
      chain: localhost,
      transport: http(rpcUrl),
    });

    const tkAddress = process.env.TK_CONTRACT_ADDRESS;
    const tkiAddress = process.env.TKI_CONTRACT_ADDRESS;
    const revenueControllerAddress = process.env.REVENUE_CONTROLLER_ADDRESS;

    if (!tkAddress || !tkiAddress || !revenueControllerAddress) {
      throw new Error('Contract addresses not set in environment variables');
    }

    this.tkContract = getContract({
      address: tkAddress as `0x${string}`,
      abi: TK_ABI,
      publicClient: this.publicClient,
      walletClient: this.walletClient,
    });

    this.tkiContract = getContract({
      address: tkiAddress as `0x${string}`,
      abi: TKI_ABI,
      publicClient: this.publicClient,
      walletClient: this.walletClient,
    });

    this.revenueControllerContract = getContract({
      address: revenueControllerAddress as `0x${string}`,
      abi: REVENUE_CONTROLLER_ABI,
      publicClient: this.publicClient,
      walletClient: this.walletClient,
    });

    logger.info('Blockchain service initialized successfully');
  }

  async mintTK(to: string, amount: string): Promise<string> {
    try {
      const hash = await this.tkContract.write.mint([to as `0x${string}`, parseEther(amount)]);
      logger.info(`TK minted successfully. Hash: ${hash}`);
      return hash;
    } catch (error) {
      logger.error('Error minting TK:', error);
      throw error;
    }
  }

  async submitClap(creator: string, amount: string, delegation: string): Promise<number> {
    try {
      const hash = await this.revenueControllerContract.write.submitClap([
        creator as `0x${string}`,
        parseEther(amount),
        delegation as `0x${string}`
      ]);
      logger.info(`Clap submitted successfully. Hash: ${hash}`);
      
      // Get the intent ID from the transaction receipt
      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      // Note: In a real implementation, you'd need to parse the event logs to get the intent ID
      return 0; // Placeholder
    } catch (error) {
      logger.error('Error submitting clap:', error);
      throw error;
    }
  }

  async submitGift(creator: string, amount: string, delegation: string): Promise<number> {
    try {
      const hash = await this.revenueControllerContract.write.submitGift([
        creator as `0x${string}`,
        parseEther(amount),
        delegation as `0x${string}`
      ]);
      logger.info(`Gift submitted successfully. Hash: ${hash}`);
      return 0; // Placeholder
    } catch (error) {
      logger.error('Error submitting gift:', error);
      throw error;
    }
  }

  async approveIntents(ids: number[], flags: boolean[]): Promise<string> {
    try {
      const hash = await this.revenueControllerContract.write.approveIntents([ids, flags]);
      logger.info(`Intents approved successfully. Hash: ${hash}`);
      return hash;
    } catch (error) {
      logger.error('Error approving intents:', error);
      throw error;
    }
  }

  async settleEpoch(intentIds: number[], creators: string[]): Promise<string> {
    try {
      const hash = await this.revenueControllerContract.write.settleEpoch([intentIds, creators]);
      logger.info(`Epoch settled successfully. Hash: ${hash}`);
      return hash;
    } catch (error) {
      logger.error('Error settling epoch:', error);
      throw error;
    }
  }

  async getBalance(address: string, token: 'tk' | 'tki'): Promise<string> {
    try {
      const contract = token === 'tk' ? this.tkContract : this.tkiContract;
      const balance = await contract.read.balanceOf([address as `0x${string}`]);
      return balance.toString();
    } catch (error) {
      logger.error(`Error getting ${token} balance:`, error);
      throw error;
    }
  }
}

export const blockchainService = new BlockchainService();
