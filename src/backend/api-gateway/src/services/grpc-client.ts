// @ts-version 5.0

// External imports with versions
import * as grpc from '@grpc/grpc-js'; // v1.9.0
import * as protoLoader from '@grpc/proto-loader'; // v0.7.0
import CircuitBreaker from 'circuit-breaker-js'; // v0.5.0
import { Counter, Histogram } from 'prom-client'; // v14.2.0

// Internal imports
import { UserService } from '../../../proto/user.proto';
import { TagService } from '../../../proto/tag.proto';
import { SpatialService } from '../../../proto/spatial.proto';
import { CommerceService } from '../../../proto/commerce.proto';
import { APIError } from '../types/index';

// Configuration interfaces
interface GrpcConfig {
  services: {
    user: { host: string; port: number };
    tag: { host: string; port: number };
    spatial: { host: string; port: number };
    commerce: { host: string; port: number };
  };
  poolSize: number;
  timeout: number;
  retryAttempts: number;
  circuitBreaker: {
    failureThreshold: number;
    resetTimeout: number;
  };
}

interface ConnectionPool {
  acquire(): Promise<grpc.Client>;
  release(client: grpc.Client): void;
  destroy(): void;
}

// Metrics setup
const grpcRequestDuration = new Histogram({
  name: 'grpc_request_duration_seconds',
  help: 'Duration of gRPC requests',
  labelNames: ['service', 'method']
});

const grpcRequestErrors = new Counter({
  name: 'grpc_request_errors_total',
  help: 'Total count of gRPC request errors',
  labelNames: ['service', 'method', 'error_type']
});

export class GrpcClient {
  private clients: Map<string, any>;
  private channels: Map<string, grpc.Channel>;
  private circuitBreakers: Map<string, CircuitBreaker>;
  private connectionPool: ConnectionPool;
  private readonly config: GrpcConfig;

  constructor(config: GrpcConfig) {
    this.config = config;
    this.clients = new Map();
    this.channels = new Map();
    this.circuitBreakers = new Map();
    this.initializeServices();
  }

  private async initializeServices(): Promise<void> {
    const protoOptions = {
      keepCase: true,
      longs: String,
      enums: String,
      defaults: true,
      oneofs: true
    };

    // Load all proto definitions
    const userProto = await protoLoader.load('../../../proto/user.proto', protoOptions);
    const tagProto = await protoLoader.load('../../../proto/tag.proto', protoOptions);
    const spatialProto = await protoLoader.load('../../../proto/spatial.proto', protoOptions);
    const commerceProto = await protoLoader.load('../../../proto/commerce.proto', protoOptions);

    // Initialize circuit breakers for each service
    const services = ['user', 'tag', 'spatial', 'commerce'];
    services.forEach(service => {
      this.circuitBreakers.set(service, new CircuitBreaker({
        failureThreshold: this.config.circuitBreaker.failureThreshold,
        resetTimeout: this.config.circuitBreaker.resetTimeout
      }));
    });

    // Create service clients
    this.createServiceClient('user', userProto, UserService);
    this.createServiceClient('tag', tagProto, TagService);
    this.createServiceClient('spatial', spatialProto, SpatialService);
    this.createServiceClient('commerce', commerceProto, CommerceService);

    // Initialize connection monitoring
    this.monitorConnections();
  }

  private createServiceClient(
    serviceName: string, 
    proto: any, 
    serviceDefinition: any
  ): void {
    const serviceConfig = this.config.services[serviceName];
    const address = `${serviceConfig.host}:${serviceConfig.port}`;
    
    const channel = new grpc.Channel(
      address,
      grpc.credentials.createInsecure(),
      {
        'grpc.keepalive_time_ms': 30000,
        'grpc.keepalive_timeout_ms': 5000,
        'grpc.http2.min_time_between_pings_ms': 10000,
        'grpc.http2.max_pings_without_data': 0
      }
    );

    const client = new serviceDefinition(channel);
    this.channels.set(serviceName, channel);
    this.clients.set(serviceName, client);
  }

  public async getUserService(): Promise<any> {
    return this.getServiceWithRetry('user');
  }

  public async getTagService(): Promise<any> {
    return this.getServiceWithRetry('tag');
  }

  public async getSpatialService(): Promise<any> {
    return this.getServiceWithRetry('spatial');
  }

  public async getCommerceService(): Promise<any> {
    return this.getServiceWithRetry('commerce');
  }

  private async getServiceWithRetry(serviceName: string): Promise<any> {
    const circuitBreaker = this.circuitBreakers.get(serviceName);
    
    return new Promise((resolve, reject) => {
      circuitBreaker.run(
        async () => {
          const client = this.clients.get(serviceName);
          if (!client) {
            throw new Error(`Service ${serviceName} not initialized`);
          }

          const wrappedClient = this.wrapClientWithMetrics(client, serviceName);
          return wrappedClient;
        },
        (err: Error) => {
          grpcRequestErrors.inc({ service: serviceName, error_type: 'circuit_breaker' });
          reject(this.handleError(err));
        }
      );
    });
  }

  private wrapClientWithMetrics(client: any, serviceName: string): any {
    const wrappedClient = {};
    
    Object.getOwnPropertyNames(Object.getPrototypeOf(client))
      .filter(prop => typeof client[prop] === 'function')
      .forEach(method => {
        wrappedClient[method] = async (...args: any[]) => {
          const timer = grpcRequestDuration.startTimer({ 
            service: serviceName, 
            method 
          });

          try {
            const result = await client[method](...args);
            timer();
            return result;
          } catch (error) {
            grpcRequestErrors.inc({ 
              service: serviceName, 
              method, 
              error_type: error.code 
            });
            throw this.handleError(error);
          }
        };
      });

    return wrappedClient;
  }

  private handleError(error: any): APIError {
    return {
      code: error.code || 500,
      message: error.message || 'Internal gRPC client error',
      details: error.details || {}
    };
  }

  public monitorConnections(): void {
    setInterval(() => {
      this.channels.forEach((channel, serviceName) => {
        const state = channel.getConnectivityState(true);
        if (state === grpc.connectivityState.TRANSIENT_FAILURE) {
          grpcRequestErrors.inc({ 
            service: serviceName, 
            error_type: 'connectivity' 
          });
          this.reconnectService(serviceName);
        }
      });
    }, 5000);
  }

  private async reconnectService(serviceName: string): Promise<void> {
    const channel = this.channels.get(serviceName);
    if (channel) {
      channel.close();
      await this.createServiceClient(
        serviceName,
        await protoLoader.load(`../../../proto/${serviceName}.proto`),
        this.clients.get(serviceName).constructor
      );
    }
  }

  public async close(): Promise<void> {
    this.channels.forEach(channel => channel.close());
    this.clients.clear();
    this.channels.clear();
    this.circuitBreakers.clear();
  }
}

// Factory function for creating GrpcClient instances
export function createGrpcClient(config: GrpcConfig): GrpcClient {
  return new GrpcClient(config);
}