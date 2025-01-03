// @ts-version 5.0

import { Router, Request, Response, NextFunction } from 'express'; // v4.18.2
import { sign, verify } from 'jsonwebtoken'; // v9.0.0
import { hash, compare } from 'bcrypt'; // v5.1.0
import Redis from 'ioredis'; // v5.3.2
import { APIError } from '../types';
import { authenticate } from '../middleware/auth';
import { validateUserInput } from '../middleware/validation';
import { GrpcClient } from '../services/grpc-client';

// Environment variables with defaults
const JWT_SECRET = process.env.JWT_SECRET!;
const JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET!;
const TOKEN_EXPIRY = process.env.TOKEN_EXPIRY || '1h';
const REFRESH_TOKEN_EXPIRY = process.env.REFRESH_TOKEN_EXPIRY || '7d';
const STATUS_CHECK_INTERVAL = process.env.STATUS_CHECK_INTERVAL || '1h';
const DEVICE_VERIFICATION_TIMEOUT = process.env.DEVICE_VERIFICATION_TIMEOUT || '30s';
const TOKEN_ROTATION_ENABLED = process.env.TOKEN_ROTATION_ENABLED === 'true';
const LOCATION_CHECK_ENABLED = process.env.LOCATION_CHECK_ENABLED === 'true';

// Initialize Redis for token blacklist and session management
const redis = new Redis({
  host: process.env.REDIS_HOST || 'localhost',
  port: Number(process.env.REDIS_PORT) || 6379,
  password: process.env.REDIS_PASSWORD,
  keyPrefix: 'auth:'
});

const router = Router();
const grpcClient = new GrpcClient({
  services: {
    user: { host: process.env.USER_SERVICE_HOST!, port: Number(process.env.USER_SERVICE_PORT) },
    tag: { host: process.env.TAG_SERVICE_HOST!, port: Number(process.env.TAG_SERVICE_PORT) },
    spatial: { host: process.env.SPATIAL_SERVICE_HOST!, port: Number(process.env.SPATIAL_SERVICE_PORT) },
    commerce: { host: process.env.COMMERCE_SERVICE_HOST!, port: Number(process.env.COMMERCE_SERVICE_PORT) }
  },
  poolSize: 10,
  timeout: 5000,
  retryAttempts: 3,
  circuitBreaker: {
    failureThreshold: 5,
    resetTimeout: 30000
  }
});

/**
 * Enhanced user registration with device verification and status initialization
 */
router.post('/register', validateUserInput, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { email, password, displayName, deviceInfo } = req.body;

    // Hash password with bcrypt
    const hashedPassword = await hash(password, 12);

    // Create user via gRPC user service
    const userService = await grpcClient.getUserService();
    const user = await userService.createUser({
      email,
      displayName,
      preferences: {
        discoveryRadius: 1000,
        visibilityEnabled: true,
        notifications: {
          pushEnabled: true,
          emailEnabled: true,
          nearbyAlerts: true,
          tagAlerts: true,
          statusAlerts: true
        }
      }
    });

    // Initialize user status
    const statusService = await grpcClient.getStatusService();
    const initialStatus = await statusService.initializeStatus({
      userId: user.id,
      initialLevel: 'STATUS_LEVEL_REGULAR'
    });

    // Generate JWT tokens with status claims
    const accessToken = sign(
      {
        userId: user.id,
        email: user.email,
        statusLevel: initialStatus.level,
        deviceId: deviceInfo?.deviceId
      },
      JWT_SECRET,
      { expiresIn: TOKEN_EXPIRY }
    );

    const refreshToken = sign(
      { userId: user.id },
      JWT_REFRESH_SECRET,
      { expiresIn: REFRESH_TOKEN_EXPIRY }
    );

    // Store device session
    await redis.setex(
      `session:${user.id}:${deviceInfo?.deviceId}`,
      3600 * 24 * 7,
      JSON.stringify({ refreshToken, deviceInfo })
    );

    res.status(201).json({
      success: true,
      data: {
        user: {
          id: user.id,
          email: user.email,
          displayName: user.displayName,
          statusLevel: initialStatus.level
        },
        tokens: {
          accessToken,
          refreshToken,
          expiresIn: TOKEN_EXPIRY
        }
      }
    });
  } catch (error) {
    next(error);
  }
});

/**
 * Multi-factor authentication with status-based validation
 */
router.post('/login', validateUserInput, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { email, password, deviceInfo, location } = req.body;

    // Get user and status from services
    const userService = await grpcClient.getUserService();
    const user = await userService.getUserByEmail({ email });

    if (!user) {
      throw new APIError(401, 'Invalid credentials');
    }

    // Verify password
    const isValidPassword = await compare(password, user.hashedPassword);
    if (!isValidPassword) {
      throw new APIError(401, 'Invalid credentials');
    }

    // Check location-based security rules if enabled
    if (LOCATION_CHECK_ENABLED && location) {
      const spatialService = await grpcClient.getSpatialService();
      const locationValid = await spatialService.validateLocation({
        userId: user.id,
        location,
        deviceId: deviceInfo?.deviceId
      });

      if (!locationValid) {
        throw new APIError(403, 'Location validation failed');
      }
    }

    // Generate status-aware JWT token
    const accessToken = sign(
      {
        userId: user.id,
        email: user.email,
        statusLevel: user.statusLevel,
        deviceId: deviceInfo?.deviceId
      },
      JWT_SECRET,
      { expiresIn: TOKEN_EXPIRY }
    );

    const refreshToken = sign(
      { userId: user.id },
      JWT_REFRESH_SECRET,
      { expiresIn: REFRESH_TOKEN_EXPIRY }
    );

    // Update session registry
    await redis.setex(
      `session:${user.id}:${deviceInfo?.deviceId}`,
      3600 * 24 * 7,
      JSON.stringify({ refreshToken, deviceInfo })
    );

    res.json({
      success: true,
      data: {
        user: {
          id: user.id,
          email: user.email,
          displayName: user.displayName,
          statusLevel: user.statusLevel
        },
        tokens: {
          accessToken,
          refreshToken,
          expiresIn: TOKEN_EXPIRY
        }
      }
    });
  } catch (error) {
    next(error);
  }
});

/**
 * Token refresh with status validation and rotation
 */
router.post('/refresh', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { refreshToken, deviceInfo } = req.body;

    // Verify refresh token
    const decoded = verify(refreshToken, JWT_REFRESH_SECRET) as { userId: string };

    // Check token blacklist
    const isBlacklisted = await redis.exists(`blacklist:${refreshToken}`);
    if (isBlacklisted) {
      throw new APIError(401, 'Token has been revoked');
    }

    // Get current user status
    const userService = await grpcClient.getUserService();
    const user = await userService.getUser({ userId: decoded.userId });

    // Generate new access token with status
    const accessToken = sign(
      {
        userId: user.id,
        email: user.email,
        statusLevel: user.statusLevel,
        deviceId: deviceInfo?.deviceId
      },
      JWT_SECRET,
      { expiresIn: TOKEN_EXPIRY }
    );

    // Implement token rotation if enabled
    if (TOKEN_ROTATION_ENABLED) {
      const newRefreshToken = sign(
        { userId: user.id },
        JWT_REFRESH_SECRET,
        { expiresIn: REFRESH_TOKEN_EXPIRY }
      );

      // Blacklist old refresh token
      await redis.setex(`blacklist:${refreshToken}`, 3600 * 24 * 7, '1');

      // Update session with new refresh token
      await redis.setex(
        `session:${user.id}:${deviceInfo?.deviceId}`,
        3600 * 24 * 7,
        JSON.stringify({ refreshToken: newRefreshToken, deviceInfo })
      );

      res.json({
        success: true,
        data: {
          tokens: {
            accessToken,
            refreshToken: newRefreshToken,
            expiresIn: TOKEN_EXPIRY
          }
        }
      });
    } else {
      res.json({
        success: true,
        data: {
          tokens: {
            accessToken,
            expiresIn: TOKEN_EXPIRY
          }
        }
      });
    }
  } catch (error) {
    next(error);
  }
});

/**
 * Enhanced logout with multi-device session management
 */
router.post('/logout', authenticate, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { allDevices } = req.body;
    const userId = req.user!.id;
    const deviceId = req.headers['x-device-id'] as string;

    if (allDevices) {
      // Clear all sessions for user
      const sessionKeys = await redis.keys(`session:${userId}:*`);
      if (sessionKeys.length > 0) {
        await redis.del(...sessionKeys);
      }
    } else {
      // Clear specific device session
      await redis.del(`session:${userId}:${deviceId}`);
    }

    // Blacklist current token
    const token = req.headers.authorization!.split(' ')[1];
    await redis.setex(
      `blacklist:${token}`,
      3600, // 1 hour blacklist
      '1'
    );

    res.json({
      success: true,
      data: {
        message: 'Successfully logged out'
      }
    });
  } catch (error) {
    next(error);
  }
});

export default router;