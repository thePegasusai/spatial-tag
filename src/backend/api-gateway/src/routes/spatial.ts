// @ts-version 5.0

import express, { Request, Response } from 'express'; // v4.18.2
import { WebSocket, WebSocketServer } from 'ws'; // v8.13.0
import { createClient } from 'redis'; // v4.6.7
import { createLogger, format, transports } from 'winston'; // v3.10.0
import { Counter, Histogram } from 'prom-client'; // v14.2.0

import { authenticate } from '../middleware/auth';
import { GrpcClient } from '../services/grpc-client';
import { APIError } from '../types';
import { 
  ScanQuality, 
  LiDARScan, 
  ProximityRequest, 
  Location 
} from '../../../proto/spatial';

// Initialize router
const router = express.Router();

// Initialize gRPC client for spatial service
const grpcClient = new GrpcClient({
  retries: 3,
  timeout: 5000,
  circuitBreaker: true
});

// Initialize Redis client for caching
const cache = createClient({
  url: process.env.REDIS_URL,
  socket: {
    reconnectStrategy: (retries) => Math.min(retries * 50, 1000)
  }
});

// Configure logger
const logger = createLogger({
  format: format.combine(
    format.timestamp(),
    format.json()
  ),
  transports: [
    new transports.Console({
      level: process.env.NODE_ENV === 'production' ? 'info' : 'debug'
    })
  ]
});

// Metrics
const scanProcessingDuration = new Histogram({
  name: 'spatial_scan_processing_duration_seconds',
  help: 'Duration of LiDAR scan processing'
});

const proximityQueriesTotal = new Counter({
  name: 'spatial_proximity_queries_total',
  help: 'Total number of proximity queries'
});

// WebSocket connections store
const wsConnections = new Map<string, WebSocket>();

/**
 * Process LiDAR scan data with validation and metrics
 */
async function processScan(req: Request, res: Response): Promise<void> {
  const timer = scanProcessingDuration.startTimer();
  
  try {
    const { scanData, deviceId, quality } = req.body;
    
    // Validate scan data
    if (!scanData || !deviceId) {
      throw new APIError(400, 'Invalid scan data', {
        required: ['scanData', 'deviceId']
      });
    }

    const scan: LiDARScan = {
      points: scanData,
      deviceId,
      scanTime: new Date().toISOString(),
      quality: quality || ScanQuality.SCAN_QUALITY_HIGH,
      batteryLevel: req.body.batteryLevel,
      deviceTemperature: req.body.deviceTemperature,
      deviceMetadata: req.body.metadata || {},
      errorCodes: []
    };

    const spatialService = await grpcClient.getSpatialService();
    const result = await spatialService.ProcessLiDARScan(scan);

    timer({ status: 'success' });
    res.json({
      success: true,
      data: result,
      metadata: {
        processingTime: timer.duration,
        quality: scan.quality
      }
    });
  } catch (error) {
    timer({ status: 'error' });
    logger.error('Scan processing error', { error, userId: req.user?.id });
    throw error;
  }
}

/**
 * Get nearby points with caching and pagination
 */
async function getNearbyPoints(req: Request, res: Response): Promise<void> {
  proximityQueriesTotal.inc();

  try {
    const { latitude, longitude, radius, quality } = req.query;
    const cacheKey = `proximity:${latitude}:${longitude}:${radius}:${req.user?.id}`;

    // Check cache
    const cachedResult = await cache.get(cacheKey);
    if (cachedResult) {
      return res.json(JSON.parse(cachedResult));
    }

    const proximityRequest: ProximityRequest = {
      origin: {
        latitude: parseFloat(latitude as string),
        longitude: parseFloat(longitude as string),
        altitude: 0,
        accuracyMeters: 1.0
      },
      radiusMeters: parseFloat(radius as string),
      userId: req.user?.id,
      includeExpired: false,
      minConfidenceScore: 0.8,
      minimumQuality: quality || ScanQuality.SCAN_QUALITY_HIGH,
      includeEnvironmentalData: true
    };

    const spatialService = await grpcClient.getSpatialService();
    const result = await spatialService.GetNearbyPoints(proximityRequest);

    // Cache result for 30 seconds
    await cache.setEx(cacheKey, 30, JSON.stringify(result));

    res.json({
      success: true,
      data: result,
      metadata: {
        timestamp: new Date().toISOString(),
        cached: false
      }
    });
  } catch (error) {
    logger.error('Proximity query error', { error, userId: req.user?.id });
    throw error;
  }
}

/**
 * Update user location with validation and throttling
 */
async function updateLocation(req: Request, res: Response): Promise<void> {
  try {
    const { latitude, longitude, altitude, accuracy } = req.body;

    const location: Location = {
      latitude,
      longitude,
      altitude: altitude || 0,
      accuracyMeters: accuracy || 1.0
    };

    const spatialService = await grpcClient.getSpatialService();
    await spatialService.UpdateUserLocation({
      location,
      deviceId: req.body.deviceId,
      timestamp: new Date().toISOString()
    });

    // Notify connected WebSocket clients
    broadcastLocationUpdate(req.user?.id!, location);

    res.json({
      success: true,
      metadata: {
        timestamp: new Date().toISOString()
      }
    });
  } catch (error) {
    logger.error('Location update error', { error, userId: req.user?.id });
    throw error;
  }
}

/**
 * Setup WebSocket connection with authentication and heartbeat
 */
function setupWebSocket(ws: WebSocket, req: Request): void {
  const userId = req.user?.id!;
  wsConnections.set(userId, ws);

  // Setup heartbeat
  const heartbeat = setInterval(() => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.ping();
    }
  }, 30000);

  ws.on('message', async (message: string) => {
    try {
      const data = JSON.parse(message);
      if (data.type === 'location') {
        const spatialService = await grpcClient.getSpatialService();
        await spatialService.UpdateUserLocation(data.payload);
      }
    } catch (error) {
      logger.error('WebSocket message error', { error, userId });
    }
  });

  ws.on('close', () => {
    clearInterval(heartbeat);
    wsConnections.delete(userId);
  });

  ws.on('error', (error) => {
    logger.error('WebSocket error', { error, userId });
    ws.close();
  });
}

/**
 * Broadcast location update to relevant WebSocket clients
 */
function broadcastLocationUpdate(userId: string, location: Location): void {
  const ws = wsConnections.get(userId);
  if (ws?.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({
      type: 'location_update',
      payload: location,
      timestamp: new Date().toISOString()
    }));
  }
}

// Route definitions
router.post('/scan', authenticate, processScan);
router.get('/nearby', authenticate, getNearbyPoints);
router.post('/location', authenticate, updateLocation);
router.ws('/updates', authenticate, setupWebSocket);

export default router;