# TikTok TechJam 2025 - Creator Economy Platform

## 🎯 Project Overview

TikTok TechJam 2025 is a revolutionary creator economy platform that combines **interest-bearing stablecoins**, **social engagement tokens**, and **delegated transfers** to create a fair and efficient system for content creators and their supporters. The platform enables users to earn interest on their deposits while supporting creators through innovative "clap" and "gift" mechanisms.

## 🏗️ System Architecture

The platform consists of two main components:

1. **Smart Contracts** - Ethereum-based DeFi infrastructure
2. **Backend Server** - TypeScript Express.js API with job processing

### **Smart Contract System**

The smart contract architecture implements a **dual-token model**:

- **TK (TikTok USD)** - A stablecoin representing real USD value
- **TKI (TikTok Interest)** - An interest-bearing token that accrues value over time

#### **Key Features:**

- **Compound-like Interest Accrual** - Global interest rate that compounds over time
- **Intent-Based Architecture** - Batches user actions for efficient processing
- **ERC-7710 Integration** - Permissionless delegation system for enhanced UX
- **Automated Settlement** - Periodic processing of approved intents
- **TKI to TK Conversion** - Converts creators' accumulated TKI to spendable TK

#### **Core Contracts:**

- `RevenueController` - Central orchestrator managing all interactions
- `TK` - Stable USD token with role-based access control
- `TKI` - Interest-bearing engagement token with actor registry
- `DelegationValidator` - ERC-7710 delegation validation

### **Backend Server Architecture**

A robust TypeScript Express.js backend with:

- **API Server** - HTTP endpoints for contract interactions
- **Job Server** - Background task processing and cron jobs
- **MongoDB** - User data and intent tracking
- **Redis** - Caching and job queues
- **BullMQ** - Advanced job scheduling and processing

## 🚀 Quick Start

### **Prerequisites**

- Node.js 18+
- Foundry (Forge, Anvil, Cast)
- Docker & Docker Compose
- MongoDB (or use Docker)
- Redis (or use Docker)

### **1. Clone and Setup**

```bash
git clone <repository-url>
cd techjam-be

# Install Foundry dependencies
forge install

# Install backend dependencies
cd server
npm install
```

### **2. Environment Configuration**

```bash
# Copy environment template
cp env.example .env

# Edit with your configuration
# - Contract addresses
# - Private keys
# - Database URLs
# - JWT secrets
```

### **3. Deploy Smart Contracts**

```bash
# Start local blockchain
anvil

# In another terminal, deploy contracts
forge script script/DeployAll.s.sol --tc DeployAll --rpc-url http://localhost:8545 --broadcast
```

### **4. Start Backend Services**

```bash
# Option 1: Docker (recommended)
docker-compose up -d

# Option 2: Local development
cd server
npm run build
npm run dev          # API server
npm run dev:job      # Job server (in another terminal)
```

## 📚 Documentation

### **Smart Contracts**

- [Contract Architecture](./CONTRACT_ARCHITECTURE.md) - Comprehensive smart contract documentation
- [Deployment Guide](./script/DeployAll.s.sol) - Contract deployment instructions

### **Backend Server**

- [Backend Architecture](./server/ARCHITECTURE.md) - Detailed backend system design
- [API Documentation](./server/README.md) - Backend server setup and usage
- [Database Schema](./server/src/models/) - Data models and relationships

## 🔧 Development

### **Smart Contract Development**

```bash
# Build contracts
forge build

# Run tests
forge test

# Run specific test
forge test --match-test testSettleEpochExecutesApprovedIntentsAndConverts

# Gas optimization
forge snapshot

# Format code
forge fmt
```

### **Backend Development**

```bash
cd server

# Development mode with hot reload
npm run dev

# Build for production
npm run build

# Run tests
npm test

# Code quality
npm run lint
npm run format
```

### **Testing**

```bash
# Smart contract tests
forge test -vvv

# Backend tests
cd server
npm test

# Integration tests
npm run test:integration
```

## 🐳 Docker Deployment

### **Complete Stack**

```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

### **Services**

| Service    | Port  | Description               |
| ---------- | ----- | ------------------------- |
| API Server | 3000  | Express.js HTTP API       |
| Job Server | 3001  | Background task processor |
| MongoDB    | 27017 | User data and intents     |
| Redis      | 6379  | Caching and job queues    |

### **Health Checks**

```bash
# API health
curl http://localhost:3000/health

# Check containers
docker-compose ps
```

## 🔐 Security Features

### **Smart Contracts**

- **Reentrancy Protection** - OpenZeppelin ReentrancyGuard
- **Access Control** - Role-based permissions
- **Input Validation** - Comprehensive parameter checks
- **Reservation System** - Prevents double-spending

### **Backend Server**

- **JWT Authentication** - Secure token-based auth
- **Rate Limiting** - Configurable per-IP limits
- **Input Validation** - Express-validator middleware
- **Security Headers** - Helmet.js protection
- **CORS Configuration** - Controlled cross-origin access

## 📊 API Endpoints

### **Authentication**

- `POST /api/auth/signup` - User registration
- `POST /api/auth/login` - User authentication
- `GET /api/auth/profile` - User profile

### **Contract Interactions**

- `POST /api/contracts/clap` - Submit TKI clap
- `POST /api/contracts/gift` - Submit TK gift
- `POST /api/contracts/mint-tk` - Mint TK after payment
- `POST /api/contracts/withdraw` - Creator withdrawal
- `GET /api/contracts/balances` - Get user balances
- `GET /api/contracts/intents` - Get user intents

### **System**

- `GET /health` - Health check endpoint

## 🔄 Background Jobs

### **Cron Jobs**

- **Settlement** - Every 7 days (processes approved intents)
- **Accrual** - Daily (interest accrual for all users)
- **Approval** - Hourly (auto-approves pending intents)

### **Job Queues**

- **Settlement Queue** - Intent processing (concurrency: 1)
- **Accrual Queue** - Interest calculations (concurrency: 5)
- **Payment Queue** - TK minting (concurrency: 3)
- **Withdrawal Queue** - Creator payouts (concurrency: 3)

## 💰 Economic Model

### **Interest Accrual**

- **Base Rate**: Configurable monthly interest (default: 2%)
- **Safety Cap**: Maximum rate limit (default: 10%)
- **Accrual Interval**: Daily index updates
- **Conversion Ratio**: 100 TKI = 1 TK

### **Creator Support**

- **Claps**: Users spend earned TKI to support creators
- **Gifts**: Users spend TK directly to support creators
- **Settlement**: Weekly batch processing of all intents
- **Conversion**: Creators' TKI automatically converted to TK

## 🧪 Testing & Quality Assurance

### **Smart Contract Testing**

- **Unit Tests** - Individual function testing
- **Integration Tests** - Contract interaction testing
- **Gas Optimization** - Performance benchmarking
- **Security Tests** - Vulnerability assessment

### **Backend Testing**

- **API Tests** - Endpoint functionality testing
- **Database Tests** - Data persistence testing
- **Job Tests** - Background task testing
- **Integration Tests** - End-to-end workflow testing

## 🚀 Deployment

### **Smart Contracts**

```bash
# Local development
forge script script/DeployAll.s.sol --tc DeployAll --rpc-url http://localhost:8545 --broadcast

# Testnet deployment
forge script script/DeployAll.s.sol --tc DeployAll --rpc-url $TESTNET_RPC --broadcast

# Mainnet deployment
forge script script/DeployAll.s.sol --tc DeployAll --rpc-url $MAINNET_RPC --broadcast
```

### **Backend Services**

```bash
# Production build
cd server
npm run build

# Start production servers
npm start          # API server
npm run start:job  # Job server

# Or use Docker
docker-compose -f docker-compose.prod.yml up -d
```

## 🔍 Monitoring & Logging

### **Smart Contracts**

- **Events** - Comprehensive state change logging
- **Indexing** - Off-chain event processing
- **Analytics** - Transaction and gas monitoring

### **Backend Services**

- **Structured Logging** - Winston-based JSON logging
- **Health Checks** - Service availability monitoring
- **Performance Metrics** - Response time and throughput
- **Error Tracking** - Comprehensive error logging

## 🤝 Contributing

### **Development Workflow**

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

### **Code Standards**

- **Smart Contracts**: Solidity style guide compliance
- **Backend**: TypeScript strict mode, ESLint rules
- **Testing**: Minimum 90% test coverage
- **Documentation**: Inline code documentation

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

### **Getting Help**

- **Issues**: Create GitHub issues for bugs or feature requests
- **Documentation**: Check the detailed architecture docs
- **Discussions**: Use GitHub Discussions for questions
- **Security**: Report security issues privately

### **Community**

- **Discord**: Join our developer community
- **Twitter**: Follow for updates and announcements
- **Blog**: Technical articles and tutorials

## 🌟 Key Innovations

### **1. Dual-Token Interest Model**

Combines stable value storage with interest-bearing engagement tokens

### **2. Intent-Based Architecture**

Batches user actions for efficiency and enables complex approval workflows

### **3. ERC-7710 Integration**

Permissionless delegation system for enhanced user experience

### **4. Automated Settlement**

Periodic batch processing with automatic TKI to TK conversion

### **5. Creator Economy Focus**

Designed specifically for content creator monetization and fan engagement

---

_TikTok TechJam 2025 represents a novel approach to creator economy monetization, combining the stability of stablecoins with the engagement of social tokens through a secure, efficient, and user-friendly system._

## 📚 Additional Resources

- [Foundry Book](https://book.getfoundry.sh/) - Foundry development framework
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/) - Secure smart contract library
- [Viem Documentation](https://viem.sh/) - TypeScript Ethereum client
- [Express.js Guide](https://expressjs.com/) - Node.js web framework
- [MongoDB Documentation](https://docs.mongodb.com/) - NoSQL database
- [Redis Documentation](https://redis.io/documentation) - In-memory data store
