// @ts-version 5.0

// External imports with versions
import express, { Express, Request, Response, NextFunction } from 'express'; // v4.18.2
import helmet from 'helmet'; // v7.1.0
import compression from 'compression'; // v1.7.4
import morgan from 'morgan'; // v1.10.0
import { register, collectDefaultMetrics } from 'prom-client'; // v14.2.0

// Internal imports
import corsMiddleware from './config/cors';
import { rateLimitConfig } from './config/rate-limit';
import { authenticate } from './middleware/auth';
import errorHandler from './middleware/error-handler';
import { StatusLevel } from '../proto/user';
import { APIError, HttpStatusCodes } from './types';

// Environment configuration
const PORT = process.env.PORT || 3000;
const NODE_ENV = process.env.NODE_ENV || 'development';
const STATUS_LEVELS = ['BASIC', 'ELITE', 'RARE'] as const;
const SPATIAL_VALIDATION_ENABLED = process.env.SPATIAL_VALIDATION_ENABLED === 'true';

// Initialize Express application
const app: Express = express();

/**
 * Configure and apply all middleware to the Express application
 * @param app Express application instance
 */
const configureMiddleware = (app: Express): void => {
  // Security middleware
  app.use(helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        scriptSrc: ["'self'", "'unsafe-inline'"],
        styleSrc: ["'self'", "'unsafe-inline'"],
        imgSrc: ["'self'", 'data:', 'https:'],
        connectSrc: ["'self'", 'https://api.spatialtag.com'],
      },
    },
    hsts: {
      maxAge: 31536000,
      includeSubDomains: true,
      preload: true,
    },
  }));

  // CORS configuration
  app.use(corsMiddleware());

  // Request compression
  app.use(compression({
    filter: (req, res) => {
      if (req.headers['x-no-compression']) {
        return false;
      }
      return compression.filter(req, res);
    },
    level: 6,
  }));

  // Request logging with status tracking
  app.use(morgan(':method :url :status :response-time ms - :res[content-length]', {
    skip: (req) => req.path === '/health' || req.path === '/metrics',
  }));

  // Body parsing middleware
  app.use(express.json({ limit: '10mb' }));
  app.use(express.urlencoded({ extended: true, limit: '10mb' }));

  // Apply rate limiting based on endpoint category
  app.use('/api/users', rateLimitConfig.userManagement);
  app.use('/api/tags', rateLimitConfig.tagOperations);
  app.use('/api/spatial', rateLimitConfig.spatialQueries);
  app.use('/api/wishlist', rateLimitConfig.wishlistManagement);
  app.use('/api/status', rateLimitConfig.statusUpdates);
};

/**
 * Configure all API routes with appropriate middleware
 * @param app Express application instance
 */
const configureRoutes = (app: Express): void => {
  // Health check endpoint
  app.get('/health', (req: Request, res: Response) => {
    res.status(HttpStatusCodes.OK).json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      environment: NODE_ENV,
    });
  });

  // Metrics endpoint for Prometheus
  app.get('/metrics', async (req: Request, res: Response) => {
    try {
      res.set('Content-Type', register.contentType);
      res.end(await register.metrics());
    } catch (error) {
      res.status(HttpStatusCodes.INTERNAL_SERVER_ERROR).end();
    }
  });

  // API routes with authentication and status-based access control
  app.use('/api', authenticate);

  // User management routes
  app.use('/api/users', require('./routes/users'));

  // Tag management routes
  app.use('/api/tags', require('./routes/tags'));

  // Spatial operations routes
  app.use('/api/spatial', require('./routes/spatial'));

  // Commerce and wishlist routes
  app.use('/api/commerce', require('./routes/commerce'));

  // Status-based feature routes
  app.use('/api/status', require('./routes/status'));

  // Error handling middleware
  app.use(errorHandler);

  // 404 handler for unmatched routes
  app.use((req: Request, res: Response) => {
    throw new APIError(
      HttpStatusCodes.NOT_FOUND,
      'Resource not found',
      { path: req.path }
    );
  });
};

/**
 * Initialize and start the Express server
 * @param app Express application instance
 */
const startServer = async (app: Express): Promise<void> => {
  try {
    // Initialize Prometheus metrics collection
    collectDefaultMetrics({
      prefix: 'spatial_tag_',
      gcDurationBuckets: [0.001, 0.01, 0.1, 1, 2, 5],
    });

    // Configure middleware and routes
    configureMiddleware(app);
    configureRoutes(app);

    // Start server
    app.listen(PORT, () => {
      console.log(`Server running in ${NODE_ENV} mode on port ${PORT}`);
      console.log(`Health check: http://localhost:${PORT}/health`);
      console.log(`Metrics: http://localhost:${PORT}/metrics`);
    });

    // Graceful shutdown handler
    process.on('SIGTERM', () => {
      console.log('SIGTERM received. Starting graceful shutdown...');
      // Implement graceful shutdown logic here
      process.exit(0);
    });

  } catch (error) {
    console.error('Failed to start server:', error);
    process.exit(1);
  }
};

// Initialize server if not in test environment
if (process.env.NODE_ENV !== 'test') {
  startServer(app);
}

// Export app instance for testing
export default app;