import { CronJob } from 'cron';
import { settlementQueue, accrualQueue } from './queue';
import { Intent } from '../models/Intent';
import { User } from '../models/User';
import { logger } from '../utils/logger';

// Settlement cron job - runs every 7 days (epoch)
export const settlementCron = new CronJob(
  '0 0 */7 * *', // Every 7 days at midnight
  async () => {
    try {
      logger.info('Running settlement cron job');
      
      // Get all approved but unsettled intents
      const pendingIntents = await Intent.find({
        approved: true,
        settled: false
      }).sort({ createdAt: 1 });
      
      if (pendingIntents.length === 0) {
        logger.info('No pending intents for settlement');
        return;
      }
      
      // Group intents by creator
      const creatorIntents = new Map<string, number[]>();
      pendingIntents.forEach(intent => {
        if (!creatorIntents.has(intent.to)) {
          creatorIntents.set(intent.to, []);
        }
        creatorIntents.get(intent.to)!.push(intent.intentId);
      });
      
      // Create settlement jobs
      for (const [creator, intentIds] of creatorIntents) {
        await settlementQueue.add('settlement', {
          intentIds,
          creators: [creator]
        }, {
          delay: 0, // Process immediately
          attempts: 3,
          backoff: {
            type: 'exponential',
            delay: 2000
          }
        });
      }
      
      logger.info(`Settlement cron job completed. ${creatorIntents.size} creators queued for settlement`);
    } catch (error) {
      logger.error('Settlement cron job failed:', error);
    }
  },
  null,
  false,
  'UTC'
);

// Accrual cron job - runs daily
export const accrualCron = new CronJob(
  '0 0 * * *', // Daily at midnight
  async () => {
    try {
      logger.info('Running accrual cron job');
      
      // Get all users with TK balances
      const users = await User.find({ actorType: 'user' });
      
      if (users.length === 0) {
        logger.info('No users found for accrual');
        return;
      }
      
      // Process accrual in batches of 100
      const batchSize = 100;
      for (let i = 0; i < users.length; i += batchSize) {
        const batch = users.slice(i, i + batchSize);
        const walletAddresses = batch.map(user => user.walletAddress);
        
        await accrualQueue.add('accrual', {
          accounts: walletAddresses
        }, {
          delay: 0,
          attempts: 3,
          backoff: {
            type: 'exponential',
            delay: 2000
          }
        });
      }
      
      logger.info(`Accrual cron job completed. ${users.length} users queued for accrual`);
    } catch (error) {
      logger.error('Accrual cron job failed:', error);
    }
  },
  null,
  false,
  'UTC'
);

// Intent approval cron job - runs every hour
export const approvalCron = new CronJob(
  '0 * * * *', // Every hour
  async () => {
    try {
      logger.info('Running intent approval cron job');
      
      // Get all pending intents that are older than 1 hour
      const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
      const pendingIntents = await Intent.find({
        approved: false,
        settled: false,
        createdAt: { $lt: oneHourAgo }
      });
      
      if (pendingIntents.length === 0) {
        logger.info('No pending intents for approval');
        return;
      }
      
      // Auto-approve intents (in production, this would involve AML checks)
      const intentIds = pendingIntents.map(intent => intent.intentId);
      const flags = new Array(intentIds.length).fill(true);
      
      // Update intents in database
      await Intent.updateMany(
        { intentId: { $in: intentIds } },
        { $set: { approved: true } }
      );
      
      logger.info(`Intent approval cron job completed. ${intentIds.length} intents auto-approved`);
    } catch (error) {
      logger.error('Intent approval cron job failed:', error);
    }
  },
  null,
  false,
  'UTC'
);

// Start all cron jobs
export const startCronJobs = (): void => {
  settlementCron.start();
  accrualCron.start();
  approvalCron.start();
  
  logger.info('All cron jobs started');
};

// Stop all cron jobs
export const stopCronJobs = (): void => {
  settlementCron.stop();
  accrualCron.stop();
  approvalCron.stop();
  
  logger.info('All cron jobs stopped');
};

// Manual trigger functions for testing
export const triggerSettlement = async (): Promise<void> => {
  await settlementCron.fireOnTick();
};

export const triggerAccrual = async (): Promise<void> => {
  await accrualCron.fireOnTick();
};

export const triggerApproval = async (): Promise<void> => {
  await approvalCron.fireOnTick();
};
