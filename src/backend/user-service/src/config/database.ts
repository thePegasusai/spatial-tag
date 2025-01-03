import mongoose from 'mongoose'; // v7.x
import { Pool } from 'pg'; // v8.x
import { DataSource } from 'typeorm'; // v0.3.x
import Logger from 'winston'; // v3.x
import retry from 'retry'; // v0.13.x

// Types for database health checking
interface DatabaseHealth {
  postgresql: {
    isConnected: boolean;
    replicaStatus?: string;
    poolSize: number;
  };
  mongodb: {
    isConnected: boolean;
    replicaStatus?: string;
    connectionCount: number;
  };
}

// Global configuration constants
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/spatial-tag-users';

const POSTGRES_CONFIG = {
  host: process.env.POSTGRES_HOST || 'localhost',
  port: parseInt(process.env.POSTGRES_PORT || '5432'),
  database: process.env.POSTGRES_DB || 'spatial_tag_users',
  user: process.env.POSTGRES_USER || 'postgres',
  password: process.env.POSTGRES_PASSWORD,
  ssl: process.env.POSTGRES_SSL === 'true',
  replicaSet: process.env.POSTGRES_REPLICA_SET === 'true'
};

const MONGO_OPTIONS = {
  useNewUrlParser: true,
  useUnifiedTopology: true,
  serverSelectionTimeoutMS: 5000,
  socketTimeoutMS: 45000,
  family: 4,
  maxPoolSize: 100,
  minPoolSize: 10,
  keepAlive: true,
  keepAliveInitialDelay: 300000,
  replicaSet: process.env.MONGO_REPLICA_SET,
  ssl: process.env.MONGO_SSL === 'true'
};

// Database connection instances
let postgresPool: Pool;
let dataSource: DataSource;

/**
 * Handles database connection failures with circuit breaker pattern
 */
async function handleConnectionFailure(error: Error, databaseType: string): Promise<void> {
  Logger.error(`${databaseType} connection failure:`, error);

  const operation = retry.operation({
    retries: 5,
    factor: 2,
    minTimeout: 1000,
    maxTimeout: 60000
  });

  return new Promise((resolve, reject) => {
    operation.attempt(async (currentAttempt) => {
      try {
        Logger.info(`Attempting ${databaseType} reconnection: Attempt ${currentAttempt}`);
        
        if (databaseType === 'PostgreSQL') {
          await initializePostgres();
        } else {
          await initializeMongo();
        }
        
        resolve();
      } catch (err) {
        if (operation.retry(err as Error)) {
          return;
        }
        reject(operation.mainError());
      }
    });
  });
}

/**
 * Initializes PostgreSQL connection with replica support
 */
async function initializePostgres(): Promise<void> {
  postgresPool = new Pool({
    ...POSTGRES_CONFIG,
    max: 20,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 2000,
  });

  // Initialize TypeORM DataSource for ORM operations
  dataSource = new DataSource({
    type: 'postgres',
    ...POSTGRES_CONFIG,
    synchronize: false,
    logging: true,
    entities: ['src/entities/**/*.ts'],
    migrations: ['src/migrations/**/*.ts'],
  });

  await dataSource.initialize();

  postgresPool.on('error', (err) => {
    Logger.error('Unexpected PostgreSQL error:', err);
    handleConnectionFailure(err, 'PostgreSQL');
  });
}

/**
 * Initializes MongoDB connection with replica set support
 */
async function initializeMongo(): Promise<void> {
  await mongoose.connect(MONGODB_URI, MONGO_OPTIONS);

  mongoose.connection.on('error', (err) => {
    Logger.error('MongoDB connection error:', err);
    handleConnectionFailure(err, 'MongoDB');
  });

  mongoose.connection.on('disconnected', () => {
    Logger.warn('MongoDB disconnected. Attempting to reconnect...');
  });

  mongoose.connection.on('reconnected', () => {
    Logger.info('MongoDB reconnected successfully');
  });
}

/**
 * Initializes database connections with monitoring and high availability support
 */
export async function initializeDatabase(): Promise<void> {
  try {
    Logger.info('Initializing database connections...');
    
    await Promise.all([
      initializePostgres(),
      initializeMongo()
    ]);

    Logger.info('Database connections established successfully');
  } catch (error) {
    Logger.error('Failed to initialize database connections:', error);
    throw error;
  }
}

/**
 * Gracefully closes all database connections
 */
export async function closeConnection(): Promise<void> {
  try {
    await Promise.all([
      postgresPool?.end(),
      dataSource?.destroy(),
      mongoose.connection?.close()
    ]);
    
    Logger.info('Database connections closed successfully');
  } catch (error) {
    Logger.error('Error closing database connections:', error);
    throw error;
  }
}

/**
 * Performs comprehensive health check on database connections
 */
export async function checkDatabaseHealth(): Promise<DatabaseHealth> {
  const health: DatabaseHealth = {
    postgresql: {
      isConnected: false,
      poolSize: 0
    },
    mongodb: {
      isConnected: false,
      connectionCount: 0
    }
  };

  try {
    // Check PostgreSQL health
    const pgClient = await postgresPool.connect();
    await pgClient.query('SELECT 1');
    pgClient.release();
    
    health.postgresql = {
      isConnected: true,
      replicaStatus: POSTGRES_CONFIG.replicaSet ? await checkPostgresReplicaStatus() : undefined,
      poolSize: postgresPool.totalCount
    };

    // Check MongoDB health
    health.mongodb = {
      isConnected: mongoose.connection.readyState === 1,
      replicaStatus: MONGO_OPTIONS.replicaSet ? await checkMongoReplicaStatus() : undefined,
      connectionCount: mongoose.connection.states.connected
    };
  } catch (error) {
    Logger.error('Health check failed:', error);
  }

  return health;
}

/**
 * Checks PostgreSQL replica status
 */
async function checkPostgresReplicaStatus(): Promise<string> {
  if (!POSTGRES_CONFIG.replicaSet) return 'Not configured';
  
  const client = await postgresPool.connect();
  try {
    const result = await client.query('SELECT pg_is_in_recovery()');
    return result.rows[0].pg_is_in_recovery ? 'Replica' : 'Primary';
  } finally {
    client.release();
  }
}

/**
 * Checks MongoDB replica status
 */
async function checkMongoReplicaStatus(): Promise<string> {
  if (!MONGO_OPTIONS.replicaSet) return 'Not configured';
  
  try {
    const status = await mongoose.connection.db.admin().replSetGetStatus();
    return status.ok === 1 ? 'Healthy' : 'Unhealthy';
  } catch (error) {
    return 'Error';
  }
}