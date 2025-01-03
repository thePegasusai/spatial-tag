// @ts-version 5.0

import { Request, Response, NextFunction } from 'express'; // v4.18.2
import { verify, TokenExpiredError, JsonWebTokenError } from 'jsonwebtoken'; // v9.0.0
import rateLimit from 'express-rate-limit'; // v6.7.0
import { StatusLevel } from '@types/user-status'; // v1.0.0
import { APIError } from './error-handler';
import { ErrorCodes } from '../types';

// Constants for configuration
const JWT_SECRET = process.env.JWT_SECRET!;
const JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET!;
const TOKEN_EXPIRY = process.env.TOKEN_EXPIRY || '1h';
const RATE_LIMIT_WINDOW = Number(process.env.RATE_LIMIT_WINDOW) || 15 * 60 * 1000; // 15 minutes
const RATE_LIMIT_MAX = Number(process.env.RATE_LIMIT_MAX) || 100;

// Interface for JWT payload
interface JWTPayload {
  userId: string;
  email: string;
  statusLevel: StatusLevel;
  iat: number;
  exp: number;
}

// Rate limiter configuration for authentication attempts
export const authRateLimiter = rateLimit({
  windowMs: RATE_LIMIT_WINDOW,
  max: RATE_LIMIT_MAX,
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req: Request, res: Response) => {
    throw new APIError(
      ErrorCodes.RATE_LIMIT_ERROR,
      'Too many authentication attempts. Please try again later.',
      { windowMs: RATE_LIMIT_WINDOW, maxAttempts: RATE_LIMIT_MAX }
    );
  }
});

/**
 * Middleware to authenticate requests using JWT tokens
 */
export const authenticate = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader) {
      throw new APIError(
        ErrorCodes.UNAUTHORIZED,
        'No authorization token provided',
        { header: 'Authorization header missing' }
      );
    }

    // Validate Authorization header format
    const [bearer, token] = authHeader.split(' ');
    if (bearer !== 'Bearer' || !token) {
      throw new APIError(
        ErrorCodes.UNAUTHORIZED,
        'Invalid authorization format',
        { expected: 'Bearer <token>' }
      );
    }

    try {
      // Verify JWT token
      const decoded = verify(token, JWT_SECRET) as JWTPayload;

      // Attach user information to request
      req.user = {
        id: decoded.userId,
        email: decoded.email,
        statusLevel: decoded.statusLevel
      };

      // Add security headers
      res.setHeader('X-Content-Type-Options', 'nosniff');
      res.setHeader('X-Frame-Options', 'DENY');
      res.setHeader('X-XSS-Protection', '1; mode=block');
      res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');

      next();
    } catch (error) {
      if (error instanceof TokenExpiredError) {
        throw new APIError(
          ErrorCodes.UNAUTHORIZED,
          'Token has expired',
          { expiredAt: error.expiredAt }
        );
      } else if (error instanceof JsonWebTokenError) {
        throw new APIError(
          ErrorCodes.UNAUTHORIZED,
          'Invalid token',
          { error: error.message }
        );
      } else {
        throw error;
      }
    }
  } catch (error) {
    next(error);
  }
};

/**
 * Middleware to check required user status level
 */
export const requireStatus = (requiredLevel: StatusLevel) => {
  return (req: Request, res: Response, next: NextFunction): void => {
    try {
      if (!req.user) {
        throw new APIError(
          ErrorCodes.UNAUTHORIZED,
          'Authentication required',
          { context: 'Status check requires authentication' }
        );
      }

      const userLevel = req.user.statusLevel;

      // Check if user meets the required status level
      if (userLevel < requiredLevel) {
        throw new APIError(
          ErrorCodes.FORBIDDEN,
          'Insufficient status level',
          {
            required: StatusLevel[requiredLevel],
            current: StatusLevel[userLevel]
          }
        );
      }

      next();
    } catch (error) {
      next(error);
    }
  };
};

// Extend Express Request type to include user property
declare global {
  namespace Express {
    interface Request {
      user?: {
        id: string;
        email: string;
        statusLevel: StatusLevel;
      };
    }
  }
}