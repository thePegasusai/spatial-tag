import * as grpc from '@grpc/grpc-js'; // v1.9.x
import * as protoLoader from '@grpc/proto-loader'; // v0.7.x
import winston from 'winston'; // v3.11.x
import { Counter, Histogram, Registry } from 'prom-client'; // v14.x
import { User, UserDocument, StatusLevel } from '../types';
import { ProfileService } from '../services/profile';
import { StatusService } from '../services/status';
import path from 'path';

// Constants
const PROTO_PATH = path.resolve(__dirname, '../../../proto/user.proto');
const REQUEST_TIMEOUT = 5000;
const MAX_CONCURRENT_CALLS = 1000;
const RATE_LIMIT_WINDOW = 60000;
const RATE_LIMIT_MAX_REQUESTS = 100;

// Metrics setup
const registry = new Registry();
const requestCounter = new Counter({
  name: 'user_service_requests_total',
  help: 'Total number of gRPC requests',
  labelNames: ['method', 'status'],
  registers: [registry]
});

const requestLatency = new Histogram({
  name: 'user_service_request_duration_seconds',
  help: 'Request duration in seconds',
  labelNames: ['method'],
  registers: [registry]
});

/**
 * Enhanced gRPC server implementation for user service operations
 */
export class UserServiceServer {
  private server: grpc.Server;
  private profileService: ProfileService;
  private statusService: typeof StatusService;
  private logger: winston.Logger;

  constructor(
    profileService: ProfileService,
    statusService: typeof StatusService,
    logger: winston.Logger
  ) {
    this.profileService = profileService;
    this.statusService = statusService;
    this.logger = logger;
    this.server = new grpc.Server({
      'grpc.max_concurrent_streams': MAX_CONCURRENT_CALLS,
      'grpc.keepalive_time_ms': 30000,
      'grpc.keepalive_timeout_ms': 10000,
      'grpc.http2.max_pings_without_data': 0,
      'grpc.http2.min_time_between_pings_ms': 10000
    });
  }

  /**
   * Initializes and starts the gRPC server
   */
  async start(port: number): Promise<void> {
    const packageDefinition = await protoLoader.load(PROTO_PATH, {
      keepCase: true,
      longs: String,
      enums: String,
      defaults: true,
      oneofs: true
    });

    const userProto = grpc.loadPackageDefinition(packageDefinition).user;

    this.server.addService(userProto.UserService.service, {
      createUser: this.createUserHandler.bind(this),
      getUser: this.getUserHandler.bind(this),
      updateStatus: this.updateStatusHandler.bind(this),
      getNearbyUsers: this.getNearbyUsersHandler.bind(this)
    });

    return new Promise((resolve, reject) => {
      this.server.bindAsync(
        `0.0.0.0:${port}`,
        grpc.ServerCredentials.createInsecure(),
        (error, port) => {
          if (error) {
            this.logger.error('Failed to bind server', { error });
            reject(error);
          } else {
            this.server.start();
            this.logger.info('gRPC server started', { port });
            resolve();
          }
        }
      );
    });
  }

  /**
   * Handles user creation requests with validation and monitoring
   */
  private async createUserHandler(
    call: grpc.ServerUnaryCall<any, any>,
    callback: grpc.sendUnaryData<any>
  ): Promise<void> {
    const timer = requestLatency.startTimer({ method: 'createUser' });
    const correlationId = call.metadata.get('x-correlation-id')[0] as string;

    try {
      const { email, password } = call.request;
      
      // Input validation
      if (!email || !password) {
        throw new Error('Email and password are required');
      }

      const user = await this.profileService.createUser(email, password);
      
      requestCounter.inc({ method: 'createUser', status: 'success' });
      timer();

      callback(null, user.toJSON());
    } catch (error) {
      this.logger.error('Create user error', { error, correlationId });
      requestCounter.inc({ method: 'createUser', status: 'error' });
      timer();
      callback({
        code: grpc.status.INTERNAL,
        message: 'Internal server error'
      });
    }
  }

  /**
   * Handles user retrieval requests with caching
   */
  private async getUserHandler(
    call: grpc.ServerUnaryCall<any, any>,
    callback: grpc.sendUnaryData<any>
  ): Promise<void> {
    const timer = requestLatency.startTimer({ method: 'getUser' });
    const correlationId = call.metadata.get('x-correlation-id')[0] as string;

    try {
      const { userId } = call.request;
      const profile = await this.profileService.getProfile(userId);

      if (!profile) {
        callback({
          code: grpc.status.NOT_FOUND,
          message: 'User not found'
        });
        return;
      }

      requestCounter.inc({ method: 'getUser', status: 'success' });
      timer();

      callback(null, profile);
    } catch (error) {
      this.logger.error('Get user error', { error, correlationId });
      requestCounter.inc({ method: 'getUser', status: 'error' });
      timer();
      callback({
        code: grpc.status.INTERNAL,
        message: 'Internal server error'
      });
    }
  }

  /**
   * Handles status update requests with points calculation
   */
  private async updateStatusHandler(
    call: grpc.ServerUnaryCall<any, any>,
    callback: grpc.sendUnaryData<any>
  ): Promise<void> {
    const timer = requestLatency.startTimer({ method: 'updateStatus' });
    const correlationId = call.metadata.get('x-correlation-id')[0] as string;

    try {
      const { userId, activityType } = call.request;
      
      await this.statusService.addPoints(userId, activityType);
      await this.statusService.updateUserStatus(userId);

      requestCounter.inc({ method: 'updateStatus', status: 'success' });
      timer();

      callback(null, {});
    } catch (error) {
      this.logger.error('Update status error', { error, correlationId });
      requestCounter.inc({ method: 'updateStatus', status: 'error' });
      timer();
      callback({
        code: grpc.status.INTERNAL,
        message: 'Internal server error'
      });
    }
  }

  /**
   * Handles nearby users discovery with spatial optimization
   */
  private async getNearbyUsersHandler(
    call: grpc.ServerUnaryCall<any, any>,
    callback: grpc.sendUnaryData<any>
  ): Promise<void> {
    const timer = requestLatency.startTimer({ method: 'getNearbyUsers' });
    const correlationId = call.metadata.get('x-correlation-id')[0] as string;

    try {
      const { location, radius } = call.request;
      
      const nearbyUsers = await this.profileService.findNearbyUsers(
        location,
        radius
      );

      requestCounter.inc({ method: 'getNearbyUsers', status: 'success' });
      timer();

      callback(null, { users: nearbyUsers });
    } catch (error) {
      this.logger.error('Get nearby users error', { error, correlationId });
      requestCounter.inc({ method: 'getNearbyUsers', status: 'error' });
      timer();
      callback({
        code: grpc.status.INTERNAL,
        message: 'Internal server error'
      });
    }
  }

  /**
   * Gracefully shuts down the server
   */
  async shutdown(): Promise<void> {
    return new Promise((resolve) => {
      this.server.tryShutdown(() => {
        this.logger.info('gRPC server shutdown complete');
        resolve();
      });
    });
  }
}

export default UserServiceServer;