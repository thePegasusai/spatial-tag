// @ts-version 5.0
import { ErrorRequestHandler, Request, Response, NextFunction } from 'express'; // v4.18.2
import { StatusCodes } from 'http-status-codes'; // v2.3.0
import { createLogger, format, transports } from 'winston'; // v3.8.2
import { APIError } from '../types';

// Configure Winston logger with correlation ID support
const logger = createLogger({
  format: format.combine(
    format.timestamp(),
    format.json(),
    format.errors({ stack: true })
  ),
  transports: [
    new transports.Console({
      level: process.env.NODE_ENV === 'production' ? 'error' : 'debug'
    })
  ]
});

// Error message constants for consistent error responses
const ERROR_MESSAGES = {
  UNAUTHORIZED: 'Authentication required',
  FORBIDDEN: 'Access denied',
  NOT_FOUND: 'Resource not found',
  VALIDATION_ERROR: 'Invalid request data',
  INTERNAL_ERROR: 'Internal server error',
  SPATIAL_ERROR: 'Spatial processing error',
  TAG_ERROR: 'Tag operation error',
  COMMERCE_ERROR: 'Commerce operation error'
} as const;

// Custom error codes for domain-specific errors
const ERROR_CODES = {
  SPATIAL_ERROR: 460,
  TAG_ERROR: 461,
  COMMERCE_ERROR: 462
} as const;

/**
 * Formats error object into standardized API error response
 * @param error - Original error object
 * @param statusCode - HTTP status code
 * @param correlationId - Request correlation ID for tracking
 * @returns Formatted APIError object
 */
const formatError = (error: Error, statusCode: number, correlationId: string): APIError => {
  let message = error.message;
  let details: Record<string, any> = {};

  // Sanitize error message in production
  if (process.env.NODE_ENV === 'production') {
    if (statusCode >= 500) {
      message = ERROR_MESSAGES.INTERNAL_ERROR;
    }
    // Remove sensitive information from error details
    details = {
      code: statusCode,
      correlationId
    };
  } else {
    details = {
      code: statusCode,
      correlationId,
      stack: error.stack,
      ...(error as any).details
    };
  }

  return {
    code: statusCode,
    message,
    details,
    correlationId
  };
};

/**
 * Express error handling middleware for standardized error processing
 */
const errorHandler: ErrorRequestHandler = (
  error: Error,
  req: Request,
  res: Response,
  next: NextFunction
): void => {
  // Generate correlation ID for error tracking
  const correlationId = req.headers['x-correlation-id'] as string || 
    Buffer.from(Math.random().toString()).toString('base64');

  // Determine appropriate status code based on error type
  let statusCode = StatusCodes.INTERNAL_SERVER_ERROR;

  if ('statusCode' in error) {
    statusCode = (error as any).statusCode;
  } else if ('code' in error) {
    statusCode = (error as any).code;
  } else {
    // Map specific error types to status codes
    switch (error.name) {
      case 'UnauthorizedError':
        statusCode = StatusCodes.UNAUTHORIZED;
        error.message = ERROR_MESSAGES.UNAUTHORIZED;
        break;
      case 'ForbiddenError':
        statusCode = StatusCodes.FORBIDDEN;
        error.message = ERROR_MESSAGES.FORBIDDEN;
        break;
      case 'ValidationError':
        statusCode = StatusCodes.UNPROCESSABLE_ENTITY;
        error.message = ERROR_MESSAGES.VALIDATION_ERROR;
        break;
      case 'NotFoundError':
        statusCode = StatusCodes.NOT_FOUND;
        error.message = ERROR_MESSAGES.NOT_FOUND;
        break;
      case 'SpatialError':
        statusCode = ERROR_CODES.SPATIAL_ERROR;
        error.message = ERROR_MESSAGES.SPATIAL_ERROR;
        break;
      case 'TagError':
        statusCode = ERROR_CODES.TAG_ERROR;
        error.message = ERROR_MESSAGES.TAG_ERROR;
        break;
      case 'CommerceError':
        statusCode = ERROR_CODES.COMMERCE_ERROR;
        error.message = ERROR_MESSAGES.COMMERCE_ERROR;
        break;
    }
  }

  // Log error with correlation ID and context
  logger.error('API Error', {
    correlationId,
    statusCode,
    path: req.path,
    method: req.method,
    error: {
      name: error.name,
      message: error.message,
      stack: error.stack
    },
    headers: req.headers,
    query: req.query,
    body: process.env.NODE_ENV === 'production' ? '[REDACTED]' : req.body
  });

  // Format and send error response
  const formattedError = formatError(error, statusCode, correlationId);

  res.status(statusCode).json({
    success: false,
    error: formattedError,
    metadata: {
      timestamp: new Date().toISOString(),
      path: req.path,
      method: req.method
    }
  });
};

export default errorHandler;