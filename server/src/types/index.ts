export interface User {
  _id?: string;
  email: string;
  password: string;
  walletAddress: string;
  actorType: 'user' | 'creator';
  createdAt: Date;
  updatedAt: Date;
}

export interface Intent {
  _id?: string;
  intentId: number;
  from: string;
  to: string;
  token: string;
  amount: string;
  kind: 'clap' | 'gift';
  delegation: string;
  delegationHash: string;
  createdAt: Date;
  approved: boolean;
  settled: boolean;
  txHash?: string;
}

export interface Payment {
  _id?: string;
  userId: string;
  amount: string;
  status: 'pending' | 'completed' | 'failed';
  txHash?: string;
  createdAt: Date;
  updatedAt: Date;
}

export interface Withdrawal {
  _id?: string;
  creatorId: string;
  amount: string;
  status: 'pending' | 'completed' | 'failed';
  txHash?: string;
  createdAt: Date;
  updatedAt: Date;
}

export interface AuthRequest {
  email: string;
  password: string;
}

export interface AuthResponse {
  token: string;
  user: Omit<User, 'password'>;
}

export interface GiftRequest {
  creatorAddress: string;
  amount: string;
  delegation: string;
}

export interface ClapRequest {
  creatorAddress: string;
  amount: string;
  delegation: string;
}

export interface PaymentRequest {
  amount: string;
}

export interface WithdrawalRequest {
  amount: string;
}

export interface JobData {
  type: 'settlement' | 'accrual' | 'payment' | 'withdrawal';
  data: any;
}

export interface ContractConfig {
  tkAddress: string;
  tkiAddress: string;
  revenueControllerAddress: string;
  validatorAddress: string;
  rpcUrl: string;
  chainId: number;
  privateKey: string;
}
