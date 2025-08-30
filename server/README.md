# TikTok TechJam Backend Server

A TypeScript Express.js backend server for interacting with TikTok TechJam smart contracts, featuring user authentication, contract interactions, and background job processing.

## 🏗️ Architecture

The backend consists of two main services:

1. **API Server** (`src/index.ts`) - Handles HTTP requests, user authentication, and contract interactions
2. **Job Server** (`src/job-server.ts`) - Processes background tasks, cron jobs, and blockchain operations

## 🚀 Features

- **User Authentication**: JWT-based auth with user/creator roles
- **Smart Contract Integration**: Viem-based blockchain interactions
- **Background Jobs**: BullMQ-powered job queues with Redis
- **Cron Jobs**: Automated settlement, accrual, and approval processes
- **Caching**: Redis-based caching for performance
- **Database**: MongoDB with Mongoose ODM
- **Security**: Helmet, CORS, rate limiting, input validation
- **Logging**: Winston-based structured logging
- **Docker**: Containerized deployment with Docker Compose

## 📋 Prerequisites

- Node.js 18+
- Docker & Docker Compose
- MongoDB (or use Docker)
- Redis (or use Docker)
- Anvil/Foundry for local blockchain

## 🛠️ Installation

1. **Clone and install dependencies:**
```bash
cd server
npm install
```

2. **Set up environment variables:**
```bash
cp env.example .env
# Edit .env with your configuration
```

3. **Build the project:**
```bash
npm run build
```

## 🐳 Docker Deployment

### Quick Start
```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

### Services
- **API Server**: http://localhost:3000
- **Job Server**: Port 3001 (internal)
- **MongoDB**: localhost:27017
- **Redis**: localhost:6379

## 🔧 Development

### Local Development
```bash
# Start MongoDB and Redis
docker-compose up mongodb redis -d

# Start API server in dev mode
npm run dev

# Start job server in dev mode
npm run start:job
```

### Available Scripts
```bash
npm run build          # Build TypeScript
npm run start          # Start production server
npm run dev            # Start dev server with hot reload
npm run start:job      # Start job server
npm run test           # Run tests
npm run lint           # Lint code
npm run format         # Format code
```

## 📡 API Endpoints

### Authentication
- `POST /api/auth/signup` - User registration
- `POST /api/auth/login` - User login
- `GET /api/auth/profile` - Get user profile

### Contracts
- `POST /api/contracts/clap` - Submit TKI clap
- `POST /api/contracts/gift` - Submit TK gift
- `POST /api/contracts/mint-tk` - Mint TK after payment
- `POST /api/contracts/withdraw` - Creator withdrawal
- `GET /api/contracts/balances` - Get user balances
- `GET /api/contracts/intents` - Get user intents

### Health
- `GET /health` - Health check endpoint

## 🔄 Background Jobs

### Job Types
- **Settlement**: Processes approved intents every 7 days
- **Accrual**: Processes interest accrual daily
- **Payment**: Handles TK minting after successful payments
- **Withdrawal**: Processes creator withdrawals

### Cron Schedule
- **Settlement**: Every 7 days at midnight UTC
- **Accrual**: Daily at midnight UTC
- **Approval**: Every hour

## 🗄️ Database Schema

### Users Collection
```typescript
{
  email: string,
  password: string (hashed),
  walletAddress: string,
  actorType: 'user' | 'creator',
  createdAt: Date,
  updatedAt: Date
}
```

### Intents Collection
```typescript
{
  intentId: number,
  from: string,
  to: string,
  token: string,
  amount: string,
  kind: 'clap' | 'gift',
  delegation: string,
  delegationHash: string,
  createdAt: Date,
  approved: boolean,
  settled: boolean,
  txHash?: string
}
```

## 🔐 Environment Variables

```bash
# Server
NODE_ENV=development
PORT=3000
JOB_SERVER_PORT=3001

# JWT
JWT_SECRET=your-secret-key
JWT_EXPIRES_IN=7d

# MongoDB
MONGODB_URI=mongodb://localhost:27017/tiktok-techjam

# Redis
REDIS_URL=redis://localhost:6379

# Blockchain
RPC_URL=http://localhost:8545
CHAIN_ID=31337
PRIVATE_KEY=your-private-key

# Contracts
TK_CONTRACT_ADDRESS=0x...
TKI_CONTRACT_ADDRESS=0x...
REVENUE_CONTROLLER_ADDRESS=0x...
VALIDATOR_ADDRESS=0x...
```

## 🚨 Security Features

- **Input Validation**: Express-validator for request validation
- **Rate Limiting**: Configurable rate limiting per IP
- **CORS**: Configurable cross-origin resource sharing
- **Helmet**: Security headers
- **JWT**: Secure token-based authentication
- **Password Hashing**: Bcrypt with configurable rounds

## 📊 Monitoring & Logging

- **Structured Logging**: Winston with JSON format
- **File Logs**: Separate error and combined log files
- **Health Checks**: Built-in health check endpoints
- **Error Handling**: Global error handler with proper HTTP status codes

## 🔧 Configuration

### Rate Limiting
```typescript
// Default: 100 requests per 15 minutes per IP
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100
```

### Caching
```typescript
// Redis cache TTL: 5 minutes
const CACHE_TTL = 300; // seconds
```

### Job Processing
```typescript
// Concurrency settings
settlementWorker: 1 (sequential)
accrualWorker: 5 (concurrent)
paymentWorker: 3 (concurrent)
withdrawalWorker: 3 (concurrent)
```

## 🧪 Testing

```bash
# Run tests
npm test

# Run with coverage
npm run test:coverage

# Run specific test file
npm test -- --testPathPattern=auth.test.ts
```

## 🚀 Production Deployment

1. **Set production environment:**
```bash
NODE_ENV=production
```

2. **Use production Docker images:**
```bash
docker-compose -f docker-compose.prod.yml up -d
```

3. **Set up reverse proxy (nginx) for SSL termination**

4. **Configure monitoring and alerting**

## 📝 API Documentation

### Authentication Flow
1. User signs up with email, password, wallet address, and actor type
2. User logs in and receives JWT token
3. Token is used in Authorization header for protected routes

### Contract Interaction Flow
1. User submits clap/gift with delegation data
2. Intent is stored in database and queued for approval
3. Cron job auto-approves intents (or manual approval)
4. Settlement cron job processes approved intents
5. Blockchain operations are executed via job queues

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📄 License

MIT License - see LICENSE file for details

## 🆘 Support

For issues and questions:
- Create an issue in the repository
- Check the logs for error details
- Verify environment variable configuration
- Ensure blockchain network is accessible
