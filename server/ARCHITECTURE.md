# Backend Architecture Diagram

## System Overview

```mermaid
graph TB
    subgraph "Client Applications"
        Web[Web App]
        Mobile[Mobile App]
        API[API Client]
    end

    subgraph "Load Balancer/API Gateway"
        LB[Load Balancer]
    end

    subgraph "Backend Services"
        subgraph "API Server (Port 3000)"
            Auth[Authentication]
            Routes[API Routes]
            Middleware[Security Middleware]
            Validation[Input Validation]
        end

        subgraph "Job Server (Port 3001)"
            Cron[Cron Jobs]
            Queues[Job Queues]
            Workers[Background Workers]
        end
    end

    subgraph "Data Layer"
        subgraph "Cache"
            Redis[(Redis)]
        end

        subgraph "Database"
            MongoDB[(MongoDB)]
        end
    end

    subgraph "Blockchain Layer"
        subgraph "Smart Contracts"
            TK[TK Token]
            TKI[TKI Token]
            RC[Revenue Controller]
            Validator[Delegation Validator]
        end

        subgraph "Blockchain Network"
            Anvil[Anvil/Foundry]
            RPC[RPC Endpoint]
        end
    end

    subgraph "External Services"
        Payment[Payment Gateway]
        AML[AML Service]
    end

    %% Client to API Server
    Web --> LB
    Mobile --> LB
    API --> LB
    LB --> Auth

    %% API Server internal flow
    Auth --> Routes
    Routes --> Middleware
    Middleware --> Validation

    %% API Server to Data Layer
    Validation --> MongoDB
    Validation --> Redis

    %% Job Server to Data Layer
    Cron --> Queues
    Queues --> Workers
    Workers --> MongoDB
    Workers --> Redis

    %% Background Jobs to Blockchain
    Workers --> RC
    Workers --> TK
    Workers --> TKI

    %% API Server to Blockchain
    Validation --> RC
    Validation --> TK
    Validation --> TKI

    %% Blockchain Network
    RC --> Anvil
    TK --> Anvil
    TKI --> Anvil
    Validator --> Anvil
    Anvil --> RPC

    %% External Integrations
    Payment --> Validation
    AML --> Workers

    %% Styling
    classDef service fill:#e1f5fe,stroke:#01579b,stroke-width:2px
    classDef data fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    classDef blockchain fill:#e8f5e8,stroke:#1b5e20,stroke-width:2px
    classDef external fill:#fff3e0,stroke:#e65100,stroke-width:2px

    class Auth,Routes,Middleware,Validation,Cron,Queues,Workers service
    class Redis,MongoDB data
    class TK,TKI,RC,Validator,Anvil,RPC blockchain
    class Payment,AML external
```

## Data Flow Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant API as API Server
    participant DB as MongoDB
    participant Cache as Redis
    participant Job as Job Server
    participant BC as Blockchain

    %% User Authentication
    U->>API: POST /api/auth/signup
    API->>DB: Create user
    DB-->>API: User created
    API-->>U: JWT token

    %% Submit Clap/Gift
    U->>API: POST /api/contracts/clap
    API->>Cache: Check balance
    Cache-->>API: Balance info
    API->>BC: Submit intent
    BC-->>API: Intent ID
    API->>DB: Store intent
    API-->>U: Success response

    %% Background Processing
    Job->>DB: Query pending intents
    DB-->>Job: Intent list
    Job->>BC: Approve intents
    BC-->>Job: Transaction hash
    Job->>DB: Update intent status

    %% Settlement Process
    Job->>DB: Query approved intents
    DB-->>Job: Intent list
    Job->>BC: Settle epoch
    BC-->>Job: Settlement complete
    Job->>DB: Mark intents settled

    %% Payment Processing
    U->>API: POST /api/contracts/mint-tk
    API->>BC: Mint tokens
    BC-->>API: Transaction hash
    API->>Cache: Update balance
    API-->>U: Success response
```

## Job Queue Architecture

```mermaid
graph LR
    subgraph "Cron Triggers"
        SettlementCron[Settlement Cron<br/>Every 7 days]
        AccrualCron[Accrual Cron<br/>Daily]
        ApprovalCron[Approval Cron<br/>Hourly]
    end

    subgraph "Job Queues"
        SettlementQ[Settlement Queue]
        AccrualQ[Accrual Queue]
        PaymentQ[Payment Queue]
        WithdrawalQ[Withdrawal Queue]
    end

    subgraph "Workers"
        SettlementW[Settlement Worker<br/>Concurrency: 1]
        AccrualW[Accrual Worker<br/>Concurrency: 5]
        PaymentW[Payment Worker<br/>Concurrency: 3]
        WithdrawalW[Withdrawal Worker<br/>Concurrency: 3]
    end

    subgraph "Blockchain Operations"
        Settle[settleEpoch]
        Accrue[accrueFor]
        Mint[mintTK]
        Burn[controllerBurn]
    end

    %% Cron to Queues
    SettlementCron --> SettlementQ
    AccrualCron --> AccrualQ

    %% Queues to Workers
    SettlementQ --> SettlementW
    AccrualQ --> AccrualW
    PaymentQ --> PaymentW
    WithdrawalQ --> WithdrawalW

    %% Workers to Blockchain
    SettlementW --> Settle
    AccrualW --> Accrue
    PaymentW --> Mint
    WithdrawalW --> Burn

    %% Styling
    classDef cron fill:#fff9c4,stroke:#f57f17,stroke-width:2px
    classDef queue fill:#e8f5e8,stroke:#2e7d32,stroke-width:2px
    classDef worker fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
    classDef blockchain fill:#fce4ec,stroke:#c2185b,stroke-width:2px

    class SettlementCron,AccrualCron,ApprovalCron cron
    class SettlementQ,AccrualQ,PaymentQ,WithdrawalQ queue
    class SettlementW,AccrualW,PaymentW,WithdrawalW worker
    class Settle,Accrue,Mint,Burn blockchain
```

## Security Architecture

```mermaid
graph TB
    subgraph "Client Layer"
        Client[Client Application]
    end

    subgraph "Security Middleware"
        CORS[CORS Policy]
        Helmet[Security Headers]
        RateLimit[Rate Limiting]
        Validation[Input Validation]
        Auth[JWT Authentication]
    end

    subgraph "Application Layer"
        Routes[API Routes]
        Controllers[Controllers]
    end

    subgraph "Data Layer"
        DB[(MongoDB)]
        Cache[(Redis)]
    end

    Client --> CORS
    CORS --> Helmet
    Helmet --> RateLimit
    RateLimit --> Validation
    Validation --> Auth
    Auth --> Routes
    Routes --> Controllers
    Controllers --> DB
    Controllers --> Cache

    %% Security Features
    classDef security fill:#ffebee,stroke:#c62828,stroke-width:2px
    classDef app fill:#e8f5e8,stroke:#2e7d32,stroke-width:2px
    classDef data fill:#f3e5f5,stroke:#4a148c,stroke-width:2px

    class CORS,Helmet,RateLimit,Validation,Auth security
    class Routes,Controllers app
    class DB,Cache data
```

## Deployment Architecture

```mermaid
graph TB
    subgraph "Docker Containers"
        subgraph "API Server Container"
            API[Express.js API]
            Port3000[Port 3000]
        end

        subgraph "Job Server Container"
            JobServer[Job Processor]
            Port3001[Port 3001]
        end

        subgraph "MongoDB Container"
            Mongo[MongoDB 7.0]
            Port27017[Port 27017]
        end

        subgraph "Redis Container"
            Redis[Redis 7.2]
            Port6379[Port 6379]
        end
    end

    subgraph "Host Machine"
        Docker[Docker Engine]
        Compose[Docker Compose]
        Network[Bridge Network]
    end

    subgraph "External"
        Blockchain[Anvil/Foundry<br/>Port 8545]
    end

    %% Container relationships
    API --> Mongo
    API --> Redis
    JobServer --> Mongo
    JobServer --> Redis
    API --> Blockchain
    JobServer --> Blockchain

    %% Docker management
    Compose --> Docker
    Docker --> Network
    Network --> API
    Network --> JobServer
    Network --> Mongo
    Network --> Redis

    %% Port mappings
    API -.-> Port3000
    JobServer -.-> Port3001
    Mongo -.-> Port27017
    Redis -.-> Port6379

    %% Styling
    classDef container fill:#e1f5fe,stroke:#01579b,stroke-width:2px
    classDef docker fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    classDef external fill:#fff3e0,stroke:#e65100,stroke-width:2px

    class API,JobServer,Mongo,Redis container
    class Docker,Compose,Network docker
    class Blockchain external
```

## Key Components

### 1. **API Server** (`src/index.ts`)
- Express.js HTTP server
- Authentication middleware
- Route handlers for contracts
- Security middleware (Helmet, CORS, rate limiting)

### 2. **Job Server** (`src/job-server.ts`)
- Background job processing
- Cron job scheduling
- Blockchain operation queuing

### 3. **Smart Contract Integration** (`src/config/blockchain.ts`)
- Viem client configuration
- Contract ABI definitions
- Blockchain operation methods

### 4. **Job Queues** (`src/jobs/queue.ts`)
- BullMQ queue management
- Worker processes
- Job scheduling and retry logic

### 5. **Cron Jobs** (`src/jobs/cron.ts`)
- Automated settlement processing
- Interest accrual
- Intent approval automation

### 6. **Data Models** (`src/models/`)
- User authentication
- Intent tracking
- Payment/withdrawal records

### 7. **API Routes** (`src/routes/`)
- Authentication endpoints
- Contract interaction endpoints
- Balance and intent queries

## Data Flow Summary

1. **User Authentication**: JWT-based auth with role-based access control
2. **Contract Interactions**: Users submit claps/gifts with delegation data
3. **Background Processing**: Jobs are queued for blockchain operations
4. **Automated Settlement**: Cron jobs process approved intents periodically
5. **Caching**: Redis caches balances and frequently accessed data
6. **Persistence**: MongoDB stores users, intents, and transaction records
7. **Blockchain Integration**: Viem handles all smart contract interactions
8. **Security**: Multiple layers of validation, rate limiting, and authentication
