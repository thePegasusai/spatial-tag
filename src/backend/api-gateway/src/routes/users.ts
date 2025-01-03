// @ts-version 5.0

import express, { Request, Response, NextFunction } from 'express'; // v4.18.2
import { rateLimit } from 'express-rate-limit'; // v6.7.0
import { StatusCodes } from 'http-status-codes'; // v2.3.0

// Internal imports
import { authenticate, requireStatus } from '../middleware/auth';
import { validateUserInput, validateSpatialData } from '../middleware/validation';
import { GrpcClient } from '../services/grpc-client';
import { APIResponse, ErrorCodes, UserResponse, ProximityResponse } from '../types';

// Initialize router
const router = express.Router();

// Initialize gRPC client
const grpcClient = new GrpcClient({
  services: {
    user: { host: process.env.USER_SERVICE_HOST || 'localhost', port: 50051 },
    spatial: { host: process.env.SPATIAL_SERVICE_HOST || 'localhost', port: 50052 },
    tag: { host: process.env.TAG_SERVICE_HOST || 'localhost', port: 50053 },
    commerce: { host: process.env.COMMERCE_SERVICE_HOST || 'localhost', port: 50054 }
  },
  poolSize: 10,
  timeout: 5000,
  retryAttempts: 3,
  circuitBreaker: {
    failureThreshold: 5,
    resetTimeout: 30000
  }
});

// Rate limiting configuration
const userRateLimit = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
  message: 'Too many requests from this IP, please try again later'
});

/**
 * Get user profile with privacy controls
 * @route GET /users/profile
 */
router.get('/profile', 
  authenticate,
  userRateLimit,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const userService = await grpcClient.getUserService();
      const userId = req.user!.id;

      const response = await userService.getUser({ userId });

      // Apply privacy filters based on user preferences
      const userProfile: UserResponse = {
        ...response.user,
        lastLocation: response.user.preferences.privacy.locationVisible ? 
          response.user.lastKnownLocation : null,
        isOnline: response.user.preferences.privacy.statusVisible
      };

      const apiResponse: APIResponse<UserResponse> = {
        success: true,
        data: userProfile,
        error: null,
        metadata: {
          timestamp: new Date().toISOString(),
          requestId: req.headers['x-request-id'] as string,
          processingTime: Date.now() - (req as any).startTime,
          region: process.env.AWS_REGION || 'unknown'
        }
      };

      res.status(StatusCodes.OK).json(apiResponse);
    } catch (error) {
      next(error);
    }
});

/**
 * Update user profile with validation
 * @route PUT /users/profile
 */
router.put('/profile',
  authenticate,
  validateUserInput,
  userRateLimit,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const userService = await grpcClient.getUserService();
      const userId = req.user!.id;

      const updateRequest = {
        userId,
        ...req.body,
        preferences: {
          ...req.body.preferences,
          privacy: {
            ...req.body.preferences?.privacy,
            // Ensure critical privacy settings are preserved
            profileVisible: req.body.preferences?.privacy?.profileVisible ?? true,
            locationVisible: req.body.preferences?.privacy?.locationVisible ?? false
          }
        }
      };

      const response = await userService.updateUser(updateRequest);

      const apiResponse: APIResponse<UserResponse> = {
        success: true,
        data: response.user,
        error: null,
        metadata: {
          timestamp: new Date().toISOString(),
          requestId: req.headers['x-request-id'] as string,
          processingTime: Date.now() - (req as any).startTime,
          region: process.env.AWS_REGION || 'unknown'
        }
      };

      res.status(StatusCodes.OK).json(apiResponse);
    } catch (error) {
      next(error);
    }
});

/**
 * Get nearby users with LiDAR precision
 * @route GET /users/nearby
 */
router.get('/nearby',
  authenticate,
  validateSpatialData,
  userRateLimit,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const spatialService = await grpcClient.getSpatialService();
      const userService = await grpcClient.getUserService();

      const { latitude, longitude, radius = 50, scanQuality = 'HIGH' } = req.query;

      // Get nearby points with LiDAR precision
      const proximityRequest = {
        origin: {
          latitude: parseFloat(latitude as string),
          longitude: parseFloat(longitude as string)
        },
        radiusMeters: Math.min(parseFloat(radius as string), 5000), // Max 5km radius
        userId: req.user!.id,
        minimumQuality: scanQuality,
        includeEnvironmentalData: true
      };

      const spatialResponse = await spatialService.getNearbyPoints(proximityRequest);

      // Get user details for discovered points
      const userIds = spatialResponse.points.map(point => point.userId);
      const usersResponse = await userService.getUsers({ userIds });

      // Combine spatial and user data with privacy filters
      const nearbyUsers = spatialResponse.points.map(point => {
        const user = usersResponse.users.find(u => u.id === point.userId);
        if (!user || !user.preferences.privacy.allowDiscovery) return null;

        return {
          user: {
            id: user.id,
            displayName: user.displayName,
            statusLevel: user.statusLevel,
            lastLocation: user.preferences.privacy.locationVisible ? point.location : null,
            isOnline: user.preferences.privacy.statusVisible
          },
          distance: point.distance,
          confidence: point.confidenceScore
        };
      }).filter(Boolean);

      const apiResponse: APIResponse<ProximityResponse> = {
        success: true,
        data: {
          users: nearbyUsers,
          searchRadius: proximityRequest.radiusMeters,
          timestamp: new Date().toISOString(),
          scanQuality: scanQuality as 'LOW' | 'MEDIUM' | 'HIGH' | 'ULTRA'
        },
        error: null,
        metadata: {
          timestamp: new Date().toISOString(),
          requestId: req.headers['x-request-id'] as string,
          processingTime: Date.now() - (req as any).startTime,
          region: process.env.AWS_REGION || 'unknown'
        }
      };

      res.status(StatusCodes.OK).json(apiResponse);
    } catch (error) {
      next(error);
    }
});

/**
 * Get user status with progression metrics
 * @route GET /users/status
 */
router.get('/status',
  authenticate,
  userRateLimit,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const userService = await grpcClient.getUserService();
      const userId = req.user!.id;

      const response = await userService.getUserStats({ userId });

      const statusResponse = {
        currentLevel: response.user.statusLevel,
        stats: response.stats,
        nextLevelProgress: {
          currentPoints: response.stats.engagementScore,
          requiredPoints: response.stats.statusLevel === 'ELITE' ? 1000 : 500,
          percentage: Math.min(
            (response.stats.engagementScore / (response.stats.statusLevel === 'ELITE' ? 1000 : 500)) * 100,
            100
          )
        },
        achievements: response.achievements,
        updatedAt: response.stats.lastStatusChange
      };

      const apiResponse: APIResponse<typeof statusResponse> = {
        success: true,
        data: statusResponse,
        error: null,
        metadata: {
          timestamp: new Date().toISOString(),
          requestId: req.headers['x-request-id'] as string,
          processingTime: Date.now() - (req as any).startTime,
          region: process.env.AWS_REGION || 'unknown'
        }
      };

      res.status(StatusCodes.OK).json(apiResponse);
    } catch (error) {
      next(error);
    }
});

export default router;