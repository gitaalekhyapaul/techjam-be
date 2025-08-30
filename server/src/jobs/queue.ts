import { Queue, Worker, QueueScheduler } from 'bullmq';
import { redisClient } from '../config/redis';
import { logger } from '../utils/logger';
import { blockchainService } from '../config/blockchain';
import { Intent } from '../models/Intent';

// Queue names
export const QUEUE_NAMES = {
  SETTLEMENT: 'settlement',
  ACCRUAL: 'accrual',
  PAYMENT: 'payment',
  WITHDRAWAL: 'withdrawal'
} as const;

// Create queues
export const settlementQueue = new Queue(QUEUE_NAMES.SETTLEMENT, {
  connection: redisClient
});

export const accrualQueue = new Queue(QUEUE_NAMES.ACCRUAL, {
  connection: redisClient
});

export const paymentQueue = new Queue(QUEUE_NAMES.PAYMENT, {
  connection: redisClient
});

export const withdrawalQueue = new Queue(QUEUE_NAMES.WITHDRAWAL, {
  connection: redisClient
});

// Create schedulers for delayed jobs
export const settlementScheduler = new QueueScheduler(QUEUE_NAMES.SETTLEMENT, {
  connection: redisClient
});

export const accrualScheduler = new QueueScheduler(QUEUE_NAMES.ACCRUAL, {
  connection: redisClient
});

// Settlement worker - processes approved intents
const settlementWorker = new Worker(QUEUE_NAMES.SETTLEMENT, async (job) => {
  try {
    const { intentIds, creators } = job.data;
    
    logger.info(`Processing settlement for ${intentIds.length} intents`);
    
    // Call blockchain settlement
    const txHash = await blockchainService.settleEpoch(intentIds, creators);
    
    // Update intents in database
    await Intent.updateMany(
      { intentId: { $in: intentIds } },
      { $set: { settled: true, txHash } }
    );
    
    logger.info(`Settlement completed. TX: ${txHash}`);
    
    return { success: true, txHash };
  } catch (error) {
    logger.error('Settlement job failed:', error);
    throw error;
  }
}, {
  connection: redisClient,
  concurrency: 1 // Process one settlement at a time
});

// Accrual worker - processes interest accrual
const accrualWorker = new Worker(QUEUE_NAMES.ACCRUAL, async (job) => {
  try {
    const { accounts } = job.data;
    
    logger.info(`Processing accrual for ${accounts.length} accounts`);
    
    // Call blockchain accrual
    // Note: This would need to be implemented in the blockchain service
    // For now, we'll just log it
    logger.info(`Accrual processed for accounts: ${accounts.join(', ')}`);
    
    return { success: true, processed: accounts.length };
  } catch (error) {
    logger.error('Accrual job failed:', error);
    throw error;
  }
}, {
  connection: redisClient,
  concurrency: 5 // Process multiple accruals concurrently
});

// Payment worker - processes TK minting
const paymentWorker = new Worker(QUEUE_NAMES.PAYMENT, async (job) => {
  try {
    const { to, amount } = job.data;
    
    logger.info(`Processing payment: ${amount} TK to ${to}`);
    
    // Mint TK on blockchain
    const txHash = await blockchainService.mintTK(to, amount);
    
    logger.info(`Payment completed. TX: ${txHash}`);
    
    return { success: true, txHash };
  } catch (error) {
    logger.error('Payment job failed:', error);
    throw error;
  }
}, {
  connection: redisClient,
  concurrency: 3
});

// Withdrawal worker - processes TK burning
const withdrawalWorker = new Worker(QUEUE_NAMES.WITHDRAWAL, async (job) => {
  try {
    const { from, amount } = job.data;
    
    logger.info(`Processing withdrawal: ${amount} TK from ${from}`);
    
    // Burn TK on blockchain
    // Note: This would need to be implemented in the blockchain service
    logger.info(`Withdrawal processed for ${from}: ${amount} TK`);
    
    return { success: true };
  } catch (error) {
    logger.error('Withdrawal job failed:', error);
    throw error;
  }
}, {
  connection: redisClient,
  concurrency: 3
});

// Error handling
settlementWorker.on('error', (error) => {
  logger.error('Settlement worker error:', error);
});

accrualWorker.on('error', (error) => {
  logger.error('Accrual worker error:', error);
});

paymentWorker.on('error', (error) => {
  logger.error('Payment worker error:', error);
});

withdrawalWorker.on('error', (error) => {
  logger.error('Withdrawal worker error:', error);
});

// Graceful shutdown
export const closeQueues = async (): Promise<void> => {
  await settlementQueue.close();
  await accrualQueue.close();
  await paymentQueue.close();
  await withdrawalQueue.close();
  await settlementScheduler.close();
  await accrualScheduler.close();
  await settlementWorker.close();
  await accrualWorker.close();
  await paymentWorker.close();
  await withdrawalWorker.close();
};

logger.info('Job queues initialized successfully');
