import mongoose, { Document, Schema } from 'mongoose';

export interface IIntent extends Document {
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

const intentSchema = new Schema<IIntent>({
  intentId: {
    type: Number,
    required: true,
    unique: true
  },
  from: {
    type: String,
    required: true,
    lowercase: true,
    match: [/^0x[a-fA-F0-9]{40}$/, 'Please enter a valid Ethereum address']
  },
  to: {
    type: String,
    required: true,
    lowercase: true,
    match: [/^0x[a-fA-F0-9]{40}$/, 'Please enter a valid Ethereum address']
  },
  token: {
    type: String,
    required: true,
    lowercase: true,
    match: [/^0x[a-fA-F0-9]{40}$/, 'Please enter a valid Ethereum address']
  },
  amount: {
    type: String,
    required: true
  },
  kind: {
    type: String,
    enum: ['clap', 'gift'],
    required: true
  },
  delegation: {
    type: String,
    required: true
  },
  delegationHash: {
    type: String,
    required: true
  },
  createdAt: {
    type: Date,
    default: Date.now
  },
  approved: {
    type: Boolean,
    default: false
  },
  settled: {
    type: Boolean,
    default: false
  },
  txHash: {
    type: String,
    required: false
  }
}, {
  timestamps: true
});

// Create indexes
intentSchema.index({ intentId: 1 });
intentSchema.index({ from: 1 });
intentSchema.index({ to: 1 });
intentSchema.index({ kind: 1 });
intentSchema.index({ approved: 1 });
intentSchema.index({ settled: 1 });
intentSchema.index({ createdAt: 1 });

export const Intent = mongoose.model<IIntent>('Intent', intentSchema);
