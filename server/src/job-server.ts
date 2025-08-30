import dotenv from 'dotenv';
import { connectDatabase } from './config/database';
import { connectRedis } from './config/redis';
import { startCronJobs, stopCronJobs } from './jobs/cron';
import { closeQueues } from './jobs/queue';
import { logger } from './utils/logger';

// Load environment variables
dotenv.config();

const JOB_SERVER_PORT = process.env.JOB_SERVER_PORT || 3001;

// Graceful shutdown
const gracefulShutdown = async (signal: string) => {
  logger.info(`Job server received ${signal}. Starting graceful shutdown...`);
  
  try {
    // Stop cron jobs
    stopCronJobs();
    
    // Close job queues
    await closeQueues();
    
    // Close database connections
    await connectDatabase();
    
    // Close Redis connections
    await connectRedis();
    
    logger.info('Job server graceful shutdown completed');
    process.exit(0);
  } catch (error) {
    logger.error('Error during job server graceful shutdown:', error);
    process.exit(1);
  }
};

// Start job server
const startJobServer = async () => {
  try {
    logger.info('Starting job server...');
    
    // Connect to databases
    await connectDatabase();
    await connectRedis();
    
    // Start cron jobs
    startCronJobs();
    
    logger.info(`Job server started successfully on port ${JOB_SERVER_PORT}`);
    logger.info(`Environment: ${process.env.NODE_ENV || 'development'}`);
    
    // Handle graceful shutdown
    process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
    process.on('SIGINT', () => gracefulShutdown('SIGINT'));
    
    // Handle uncaught exceptions
    process.on('uncaughtException', (error) => {
      logger.error('Job server uncaught exception:', error);
      process.exit(1);
    });
    
    process.on('unhandledRejection', (reason, promise) => {
      logger.error('Job server unhandled rejection at:', promise, 'reason:', reason);
      process.exit(1);
    });
    
  } catch (error) {
    logger.error('Failed to start job server:', error);
    process.exit(1);
  }
};

// Start the job server
startJobServer();
