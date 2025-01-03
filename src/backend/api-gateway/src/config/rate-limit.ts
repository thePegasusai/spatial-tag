// @ts-version 5.0

// External imports with versions
import rateLimit from 'express-rate-limit'; // v7.1.x
import RedisStore from 'rate-limit-redis'; // v4.0.x
import Redis from 'ioredis'; // v5.3.x

// Internal imports
import { StatusLevel } from '../types';

// Constants for rate limiting configuration
const DEFAULT_WINDOW_MS = 60000; // 1 minute in milliseconds

// Base rate limits per minute for different endpoint categories
const RATE_LIMITS = {
  USER_MANAGEMENT: 100,
  TAG_OPERATIONS: 50,
  SPATIAL_QUERIES: 200,
  WISHLIST_MANAGEMENT: 50,
  STATUS_UPDATES: 20,
} as const;

// Status-based multipliers for rate limits
const STATUS_MULTIPLIERS = {
  [StatusLevel.BASIC]: 1,
  [StatusLevel.ELITE]: 2,
  [StatusLevel.RARE]: 3,
} as const;

// Redis configuration for distributed rate limiting
const REDIS_CONFIG = {
  prefix: 'rl:', // Rate limit prefix for Redis keys
  connectionTimeout: 5000,
  maxRetries: 3,
} as const;

// Interface for rate limiter options
interface RateLimitOptions {
  windowMs: number;
  max: number;
  statusLevel: StatusLevel;
  message: string;
  standardHeaders: boolean;
  legacyHeaders: boolean;
  store: RedisStore;
}

// Interface for rate limit response
interface RateLimitResponse {
  status: number;
  message: string;
  retryAfter: number;
  limit: number;
  remaining: number;
}

// Initialize Redis client for rate limiting
const redisClient = new Redis({
  host: process.env.REDIS_HOST || 'localhost',
  port: parseInt(process.env.REDIS_PORT || '6379'),
  password: process.env.REDIS_PASSWORD,
  connectTimeout: REDIS_CONFIG.connectionTimeout,
  maxRetriesPerRequest: REDIS_CONFIG.maxRetries,
  enableOfflineQueue: true,
});

/**
 * Calculate effective rate limit based on user status
 * @param baseLimit Base rate limit per minute
 * @param userStatus User's status level
 * @returns Calculated rate limit with status multiplier
 */
const calculateRateLimit = (baseLimit: number, userStatus: StatusLevel): number => {
  const multiplier = STATUS_MULTIPLIERS[userStatus] || STATUS_MULTIPLIERS[StatusLevel.BASIC];
  return baseLimit * multiplier;
};

/**
 * Create rate limiter middleware with Redis store and status-based limits
 * @param options Rate limiter configuration options
 * @returns Configured rate limiter middleware
 */
const createRateLimiter = (options: Partial<RateLimitOptions>) => {
  const store = new RedisStore({
    prefix: REDIS_CONFIG.prefix,
    // @ts-ignore - Type definitions mismatch in rate-limit-redis
    client: redisClient,
    sendCommand: (...args: string[]) => redisClient.call(...args),
  });

  const effectiveLimit = calculateRateLimit(
    options.max || RATE_LIMITS.USER_MANAGEMENT,
    options.statusLevel || StatusLevel.BASIC
  );

  return rateLimit({
    windowMs: options.windowMs || DEFAULT_WINDOW_MS,
    max: effectiveLimit,
    standardHeaders: options.standardHeaders ?? true,
    legacyHeaders: options.legacyHeaders ?? false,
    store,
    handler: (req, res) => {
      const response: RateLimitResponse = {
        status: 429,
        message: options.message || 'Too many requests, please try again later.',
        retryAfter: Math.ceil(options.windowMs! / 1000),
        limit: effectiveLimit,
        remaining: 0,
      };
      res.status(429).json(response);
    },
    skip: (req) => req.method === 'OPTIONS',
    keyGenerator: (req) => {
      return `${REDIS_CONFIG.prefix}${req.ip}-${req.path}`;
    },
  });
};

// Export configured rate limiters for different API endpoints
export const rateLimitConfig = {
  userManagement: createRateLimiter({
    max: RATE_LIMITS.USER_MANAGEMENT,
    message: 'User management rate limit exceeded',
  }),

  tagOperations: createRateLimiter({
    max: RATE_LIMITS.TAG_OPERATIONS,
    message: 'Tag operations rate limit exceeded',
  }),

  spatialQueries: createRateLimiter({
    max: RATE_LIMITS.SPATIAL_QUERIES,
    message: 'Spatial queries rate limit exceeded',
  }),

  wishlistManagement: createRateLimiter({
    max: RATE_LIMITS.WISHLIST_MANAGEMENT,
    message: 'Wishlist management rate limit exceeded',
  }),

  statusUpdates: createRateLimiter({
    max: RATE_LIMITS.STATUS_UPDATES,
    message: 'Status updates rate limit exceeded',
  }),
};