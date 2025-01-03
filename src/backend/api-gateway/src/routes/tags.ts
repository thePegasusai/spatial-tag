// @ts-version 5.0

import { Router, Request, Response, NextFunction } from 'express'; // v4.18.2
import { StatusCodes } from 'http-status-codes'; // v2.3.0
import winston from 'winston'; // v3.11.0
import { RateLimit } from 'rate-limiter-flexible'; // v2.4.1
import { Server } from 'socket.io'; // v4.7.2

import { authenticate } from '../middleware/auth';
import { validateTagData, validateSpatialData } from '../middleware/validation';
import { GrpcClient } from '../services/grpc-client';
import { APIError, TagVisibility, StatusLevel, WebSocketMessage } from '../types';

// Initialize logger
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.json(),
  transports: [
    new winston.transports.Console()
  ]
});

// Initialize gRPC client with configuration
const grpcClient = new GrpcClient({
  poolSize: 10,
  timeout: 5000,
  retries: 3,
  services: {
    tag: { host: process.env.TAG_SERVICE_HOST!, port: Number(process.env.TAG_SERVICE_PORT) },
    spatial: { host: process.env.SPATIAL_SERVICE_HOST!, port: Number(process.env.SPATIAL_SERVICE_PORT) }
  }
});

// Initialize rate limiter
const rateLimiter = new RateLimit({
  points: 100,
  duration: 60,
  blockDuration: 60,
  keyPrefix: 'tags-api'
});

const router = Router();

/**
 * Create a new spatial tag
 * POST /tags
 */
router.post('/', 
  authenticate,
  validateTagData,
  validateSpatialData,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { content, location, expiresAt, visibilityRadius, visibility, mediaUrls } = req.body;
      const userId = req.user!.id;
      const userStatus = req.user!.statusLevel;

      // Validate user privileges based on tag visibility
      if (visibility === TagVisibility.ELITE_ONLY && userStatus < StatusLevel.ELITE) {
        throw new APIError(StatusCodes.FORBIDDEN, 'Elite status required to create Elite-only tags');
      }

      // Get gRPC services
      const spatialService = await grpcClient.getSpatialService();
      const tagService = await grpcClient.getTagService();

      // Validate location precision with LiDAR requirements
      const spatialValidation = await spatialService.validateLocation({
        location,
        requiredPrecision: 0.1 // 10cm precision
      });

      if (!spatialValidation.isValid) {
        throw new APIError(
          StatusCodes.UNPROCESSABLE_ENTITY,
          'Location precision does not meet LiDAR requirements',
          spatialValidation.details
        );
      }

      // Create tag through gRPC
      const tag = await tagService.createTag({
        creatorId: userId,
        content,
        location,
        expiresAt,
        visibilityRadius,
        visibility,
        mediaUrls,
        minViewerStatus: visibility === TagVisibility.ELITE_ONLY ? StatusLevel.ELITE : StatusLevel.REGULAR
      });

      // Notify nearby users through WebSocket
      const io: Server = req.app.get('io');
      const wsMessage: WebSocketMessage = {
        type: 'TAG_UPDATE',
        payload: {
          type: 'CREATE',
          tag
        },
        timestamp: new Date().toISOString(),
        userId
      };

      io.to(`location:${location.latitude}:${location.longitude}`).emit('tag-update', wsMessage);

      // Log tag creation
      logger.info('Tag created', {
        tagId: tag.id,
        userId,
        location: {
          lat: location.latitude,
          lng: location.longitude
        }
      });

      res.status(StatusCodes.CREATED).json({
        success: true,
        data: tag,
        metadata: {
          timestamp: new Date().toISOString()
        }
      });
    } catch (error) {
      next(error);
    }
  }
);

/**
 * Get nearby tags based on location
 * GET /tags/nearby
 */
router.get('/nearby',
  authenticate,
  validateSpatialData,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { latitude, longitude, radius = 50 } = req.query;
      const userStatus = req.user!.statusLevel;

      const tagService = await grpcClient.getTagService();
      
      const nearbyTags = await tagService.getNearbyTags({
        location: {
          latitude: Number(latitude),
          longitude: Number(longitude)
        },
        radius: Number(radius),
        visibilityFilter: TagVisibility.PUBLIC,
        viewerStatus: userStatus,
        includeExpired: false,
        limit: 50
      });

      res.json({
        success: true,
        data: nearbyTags,
        metadata: {
          timestamp: new Date().toISOString(),
          searchRadius: radius
        }
      });
    } catch (error) {
      next(error);
    }
  }
);

/**
 * Get tag by ID
 * GET /tags/:id
 */
router.get('/:id',
  authenticate,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { id } = req.params;
      const userStatus = req.user!.statusLevel;

      const tagService = await grpcClient.getTagService();
      const tag = await tagService.getTag({ id });

      if (!tag) {
        throw new APIError(StatusCodes.NOT_FOUND, 'Tag not found');
      }

      // Check visibility permissions
      if (tag.minViewerStatus > userStatus) {
        throw new APIError(StatusCodes.FORBIDDEN, 'Insufficient status level to view this tag');
      }

      res.json({
        success: true,
        data: tag,
        metadata: {
          timestamp: new Date().toISOString()
        }
      });
    } catch (error) {
      next(error);
    }
  }
);

/**
 * Update tag
 * PUT /tags/:id
 */
router.put('/:id',
  authenticate,
  validateTagData,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { id } = req.params;
      const userId = req.user!.id;
      const updates = req.body;

      const tagService = await grpcClient.getTagService();
      const existingTag = await tagService.getTag({ id });

      if (!existingTag) {
        throw new APIError(StatusCodes.NOT_FOUND, 'Tag not found');
      }

      if (existingTag.creatorId !== userId) {
        throw new APIError(StatusCodes.FORBIDDEN, 'Not authorized to update this tag');
      }

      const updatedTag = await tagService.updateTag({
        tagId: id,
        ...updates
      });

      // Notify about update through WebSocket
      const io: Server = req.app.get('io');
      const wsMessage: WebSocketMessage = {
        type: 'TAG_UPDATE',
        payload: {
          type: 'UPDATE',
          tag: updatedTag
        },
        timestamp: new Date().toISOString(),
        userId
      };

      io.to(`tag:${id}`).emit('tag-update', wsMessage);

      res.json({
        success: true,
        data: updatedTag,
        metadata: {
          timestamp: new Date().toISOString()
        }
      });
    } catch (error) {
      next(error);
    }
  }
);

/**
 * Delete tag
 * DELETE /tags/:id
 */
router.delete('/:id',
  authenticate,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { id } = req.params;
      const userId = req.user!.id;

      const tagService = await grpcClient.getTagService();
      const existingTag = await tagService.getTag({ id });

      if (!existingTag) {
        throw new APIError(StatusCodes.NOT_FOUND, 'Tag not found');
      }

      if (existingTag.creatorId !== userId) {
        throw new APIError(StatusCodes.FORBIDDEN, 'Not authorized to delete this tag');
      }

      await tagService.deleteTag({ id });

      // Notify about deletion through WebSocket
      const io: Server = req.app.get('io');
      const wsMessage: WebSocketMessage = {
        type: 'TAG_UPDATE',
        payload: {
          type: 'DELETE',
          tagId: id
        },
        timestamp: new Date().toISOString(),
        userId
      };

      io.to(`tag:${id}`).emit('tag-update', wsMessage);

      res.status(StatusCodes.NO_CONTENT).send();
    } catch (error) {
      next(error);
    }
  }
);

export default router;