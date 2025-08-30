// MongoDB initialization script
db = db.getSiblingDB('tiktok-techjam');

// Create collections with validation
db.createCollection('users', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['email', 'password', 'walletAddress', 'actorType'],
      properties: {
        email: {
          bsonType: 'string',
          pattern: '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$'
        },
        password: {
          bsonType: 'string',
          minLength: 6
        },
        walletAddress: {
          bsonType: 'string',
          pattern: '^0x[a-fA-F0-9]{40}$'
        },
        actorType: {
          enum: ['user', 'creator']
        }
      }
    }
  }
});

db.createCollection('intents', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['intentId', 'from', 'to', 'token', 'amount', 'kind', 'delegation', 'delegationHash'],
      properties: {
        intentId: {
          bsonType: 'number'
        },
        from: {
          bsonType: 'string',
          pattern: '^0x[a-fA-F0-9]{40}$'
        },
        to: {
          bsonType: 'string',
          pattern: '^0x[a-fA-F0-9]{40}$'
        },
        token: {
          bsonType: 'string',
          pattern: '^0x[a-fA-F0-9]{40}$'
        },
        amount: {
          bsonType: 'string'
        },
        kind: {
          enum: ['clap', 'gift']
        },
        delegation: {
          bsonType: 'string'
        },
        delegationHash: {
          bsonType: 'string'
        }
      }
    }
  }
});

// Create indexes
db.users.createIndex({ "email": 1 }, { unique: true });
db.users.createIndex({ "walletAddress": 1 }, { unique: true });
db.users.createIndex({ "actorType": 1 });

db.intents.createIndex({ "intentId": 1 }, { unique: true });
db.intents.createIndex({ "from": 1 });
db.intents.createIndex({ "to": 1 });
db.intents.createIndex({ "kind": 1 });
db.intents.createIndex({ "approved": 1 });
db.intents.createIndex({ "settled": 1 });
db.intents.createIndex({ "createdAt": 1 });

print('MongoDB initialization completed for tiktok-techjam database');
