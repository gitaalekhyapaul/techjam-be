import { Router, Request, Response } from 'express';
import { body, validationResult } from 'express-validator';
import { blockchainService } from '../config/blockchain';
import { Intent } from '../models/Intent';
import { authenticateToken, requireUser, requireCreator, AuthRequest } from '../utils/auth';
import { logger } from '../utils/logger';
import { redisClient } from '../config/redis';

const router = Router();

// Validation rules
const clapValidation = [
  body('creatorAddress').matches(/^0x[a-fA-F0-9]{40}$/),
  body('amount').isString().notEmpty(),
  body('delegation').isString().notEmpty()
];

const giftValidation = [
  body('creatorAddress').matches(/^0x[a-fA-F0-9]{40}$/),
  body('amount').isString().notEmpty(),
  body('delegation').isString().notEmpty()
];

const paymentValidation = [
  body('amount').isString().notEmpty()
];

const withdrawalValidation = [
  body('amount').isString().notEmpty()
];

// Submit a clap (TKI)
router.post('/clap', authenticateToken, requireUser, clapValidation, async (req: AuthRequest, res: Response) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ errors: errors.array() });
    }

    const { creatorAddress, amount, delegation } = req.body;
    const user = req.user!;

    // Check if user has enough TKI balance
    const tkiBalance = await blockchainService.getBalance(user.walletAddress, 'tki');
    if (parseFloat(tkiBalance) < parseFloat(amount)) {
      return res.status(400).json({ error: 'Insufficient TKI balance' });
    }

    // Submit clap to blockchain
    const intentId = await blockchainService.submitClap(creatorAddress, amount, delegation);

    // Store intent in database
    const intent = new Intent({
      intentId,
      from: user.walletAddress,
      to: creatorAddress.toLowerCase(),
      token: process.env.TKI_CONTRACT_ADDRESS,
      amount,
      kind: 'clap',
      delegation,
      delegationHash: require('crypto').createHash('sha256').update(delegation).digest('hex')
    });

    await intent.save();

    // Cache user's clap capacity
    const cacheKey = `clap_capacity:${user.walletAddress}`;
    await redisClient.setEx(cacheKey, 300, '0'); // Cache for 5 minutes

    logger.info(`Clap submitted: ${user.email} -> ${creatorAddress} (${amount} TKI)`);

    res.status(201).json({
      message: 'Clap submitted successfully',
      intentId,
      intent: intent
    });
  } catch (error) {
    logger.error('Clap submission error:', error);
    res.status(500).json({ error: 'Failed to submit clap' });
  }
});

// Submit a gift (TK)
router.post('/gift', authenticateToken, requireUser, giftValidation, async (req: AuthRequest, res: Response) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ errors: errors.array() });
    }

    const { creatorAddress, amount, delegation } = req.body;
    const user = req.user!;

    // Check if user has enough TK balance
    const tkBalance = await blockchainService.getBalance(user.walletAddress, 'tk');
    if (parseFloat(tkBalance) < parseFloat(amount)) {
      return res.status(400).json({ error: 'Insufficient TK balance' });
    }

    // Submit gift to blockchain
    const intentId = await blockchainService.submitGift(creatorAddress, amount, delegation);

    // Store intent in database
    const intent = new Intent({
      intentId,
      from: user.walletAddress,
      to: creatorAddress.toLowerCase(),
      token: process.env.TK_CONTRACT_ADDRESS,
      amount,
      kind: 'gift',
      delegation,
      delegationHash: require('crypto').createHash('sha256').update(delegation).digest('hex')
    });

    await intent.save();

    logger.info(`Gift submitted: ${user.email} -> ${creatorAddress} (${amount} TK)`);

    res.status(201).json({
      message: 'Gift submitted successfully',
      intentId,
      intent: intent
    });
  } catch (error) {
    logger.error('Gift submission error:', error);
    res.status(500).json({ error: 'Failed to submit gift' });
  }
});

// Mint TK after successful payment (admin only)
router.post('/mint-tk', authenticateToken, requireUser, paymentValidation, async (req: AuthRequest, res: Response) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ errors: errors.array() });
    }

    const { amount } = req.body;
    const user = req.user!;

    // Mint TK to user's wallet
    const txHash = await blockchainService.mintTK(user.walletAddress, amount);

    // Cache user's TK balance
    const cacheKey = `tk_balance:${user.walletAddress}`;
    await redisClient.setEx(cacheKey, 300, amount); // Cache for 5 minutes

    logger.info(`TK minted: ${user.email} received ${amount} TK`);

    res.json({
      message: 'TK minted successfully',
      txHash,
      amount,
      walletAddress: user.walletAddress
    });
  } catch (error) {
    logger.error('TK minting error:', error);
    res.status(500).json({ error: 'Failed to mint TK' });
  }
});

// Creator withdrawal (burn TK)
router.post('/withdraw', authenticateToken, requireCreator, withdrawalValidation, async (req: AuthRequest, res: Response) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ errors: errors.array() });
    }

    const { amount } = req.body;
    const user = req.user!;

    // Check if creator has enough TK balance
    const tkBalance = await blockchainService.getBalance(user.walletAddress, 'tk');
    if (parseFloat(tkBalance) < parseFloat(amount)) {
      return res.status(400).json({ error: 'Insufficient TK balance' });
    }

    // Burn TK from creator's wallet
    const txHash = await blockchainService.mintTK(user.walletAddress, amount);

    // Clear cache
    const cacheKey = `tk_balance:${user.walletAddress}`;
    await redisClient.del(cacheKey);

    logger.info(`Creator withdrawal: ${user.email} withdrew ${amount} TK`);

    res.json({
      message: 'Withdrawal successful',
      txHash,
      amount,
      walletAddress: user.walletAddress
    });
  } catch (error) {
    logger.error('Withdrawal error:', error);
    res.status(500).json({ error: 'Failed to process withdrawal' });
  }
});

// Get user's balances
router.get('/balances', authenticateToken, requireUser, async (req: AuthRequest, res: Response) => {
  try {
    const user = req.user!;

    // Try to get from cache first
    const tkCacheKey = `tk_balance:${user.walletAddress}`;
    const tkiCacheKey = `tki_balance:${user.walletAddress}`;

    let tkBalance = await redisClient.get(tkCacheKey);
    let tkiBalance = await redisClient.get(tkiCacheKey);

    // If not in cache, fetch from blockchain
    if (!tkBalance) {
      tkBalance = await blockchainService.getBalance(user.walletAddress, 'tk');
      await redisClient.setEx(tkCacheKey, 300, tkBalance);
    }

    if (!tkiBalance) {
      tkiBalance = await blockchainService.getBalance(user.walletAddress, 'tki');
      await redisClient.setEx(tkiCacheKey, 300, tkiBalance);
    }

    res.json({
      walletAddress: user.walletAddress,
      tkBalance,
      tkiBalance
    });
  } catch (error) {
    logger.error('Balance fetch error:', error);
    res.status(500).json({ error: 'Failed to fetch balances' });
  }
});

// Get user's intents
router.get('/intents', authenticateToken, requireUser, async (req: AuthRequest, res: Response) => {
  try {
    const user = req.user!;
    const intents = await Intent.find({
      $or: [{ from: user.walletAddress }, { to: user.walletAddress }]
    }).sort({ createdAt: -1 });

    res.json({ intents });
  } catch (error) {
    logger.error('Intents fetch error:', error);
    res.status(500).json({ error: 'Failed to fetch intents' });
  }
});

export default router;
