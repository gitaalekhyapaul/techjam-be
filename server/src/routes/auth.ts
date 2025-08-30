import { Router, Request, Response } from 'express';
import { body, validationResult } from 'express-validator';
import { User } from '../models/User';
import { generateToken } from '../utils/auth';
import { logger } from '../utils/logger';

const router = Router();

// Validation rules
const signupValidation = [
  body('email').isEmail().normalizeEmail(),
  body('password').isLength({ min: 6 }),
  body('walletAddress').matches(/^0x[a-fA-F0-9]{40}$/),
  body('actorType').isIn(['user', 'creator'])
];

const loginValidation = [
  body('email').isEmail().normalizeEmail(),
  body('password').notEmpty()
];

// Signup route
router.post('/signup', signupValidation, async (req: Request, res: Response) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ errors: errors.array() });
    }

    const { email, password, walletAddress, actorType } = req.body;

    // Check if user already exists
    const existingUser = await User.findOne({
      $or: [{ email }, { walletAddress }]
    });

    if (existingUser) {
      return res.status(400).json({
        error: 'User with this email or wallet address already exists'
      });
    }

    // Create new user
    const user = new User({
      email,
      password,
      walletAddress: walletAddress.toLowerCase(),
      actorType
    });

    await user.save();

    // Generate JWT token
    const token = generateToken(user._id.toString());

    // Return user data (without password) and token
    const userResponse = {
      _id: user._id,
      email: user.email,
      walletAddress: user.walletAddress,
      actorType: user.actorType,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt
    };

    logger.info(`New user signed up: ${email} (${actorType})`);

    res.status(201).json({
      message: 'User created successfully',
      token,
      user: userResponse
    });
  } catch (error) {
    logger.error('Signup error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Login route
router.post('/login', loginValidation, async (req: Request, res: Response) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ errors: errors.array() });
    }

    const { email, password } = req.body;

    // Find user by email
    const user = await User.findOne({ email });
    if (!user) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Check password
    const isPasswordValid = await user.comparePassword(password);
    if (!isPasswordValid) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Generate JWT token
    const token = generateToken(user._id.toString());

    // Return user data (without password) and token
    const userResponse = {
      _id: user._id,
      email: user.email,
      walletAddress: user.walletAddress,
      actorType: user.actorType,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt
    };

    logger.info(`User logged in: ${email}`);

    res.json({
      message: 'Login successful',
      token,
      user: userResponse
    });
  } catch (error) {
    logger.error('Login error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get current user profile
router.get('/profile', async (req: Request, res: Response) => {
  try {
    // This would typically use the authenticateToken middleware
    // For now, we'll return a placeholder
    res.json({ message: 'Profile endpoint - requires authentication' });
  } catch (error) {
    logger.error('Profile error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
