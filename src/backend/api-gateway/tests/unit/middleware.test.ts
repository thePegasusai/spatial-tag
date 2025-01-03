// @ts-version 5.0
import { Request, Response, NextFunction } from 'express'; // v4.18.2
import { sign } from 'jsonwebtoken'; // v9.0.0
import { RateLimiterMemory } from 'rate-limiter-flexible'; // v2.4.1
import { authenticate, requireEliteStatus } from '../../src/middleware/auth';
import { errorHandler } from '../../src/middleware/error-handler';
import { validateSchema, validateSpatialData, validateTagData } from '../../src/middleware/validation';
import { StatusLevel } from '../../../proto/user';
import { ErrorCodes } from '../../src/types';

// Mock environment variables
process.env.JWT_SECRET = 'test-secret-key';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret';

// Mock request/response objects
const mockRequest = () => {
  return {
    headers: {},
    body: {},
    user: undefined
  } as Partial<Request>;
};

const mockResponse = () => {
  const res = {} as Partial<Response>;
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  res.setHeader = jest.fn().mockReturnValue(res);
  return res;
};

const mockNext: NextFunction = jest.fn();

describe('Authentication Middleware Tests', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('authenticate middleware', () => {
    it('should authenticate valid JWT token', async () => {
      const token = sign(
        { userId: '123', email: 'test@example.com', statusLevel: StatusLevel.STATUS_LEVEL_ELITE },
        process.env.JWT_SECRET!,
        { expiresIn: '1h' }
      );

      const req = mockRequest();
      req.headers = { authorization: `Bearer ${token}` };
      const res = mockResponse();

      await authenticate(req as Request, res as Response, mockNext);

      expect(req.user).toBeDefined();
      expect(req.user?.id).toBe('123');
      expect(req.user?.statusLevel).toBe(StatusLevel.STATUS_LEVEL_ELITE);
      expect(mockNext).toHaveBeenCalledWith();
    });

    it('should reject missing authorization header', async () => {
      const req = mockRequest();
      const res = mockResponse();

      await authenticate(req as Request, res as Response, mockNext);

      expect(mockNext).toHaveBeenCalledWith(
        expect.objectContaining({
          code: ErrorCodes.UNAUTHORIZED,
          message: 'No authorization token provided'
        })
      );
    });

    it('should reject invalid token format', async () => {
      const req = mockRequest();
      req.headers = { authorization: 'InvalidFormat token123' };
      const res = mockResponse();

      await authenticate(req as Request, res as Response, mockNext);

      expect(mockNext).toHaveBeenCalledWith(
        expect.objectContaining({
          code: ErrorCodes.UNAUTHORIZED,
          message: 'Invalid authorization format'
        })
      );
    });

    it('should reject expired token', async () => {
      const token = sign(
        { userId: '123', email: 'test@example.com', statusLevel: StatusLevel.STATUS_LEVEL_ELITE },
        process.env.JWT_SECRET!,
        { expiresIn: '0s' }
      );

      const req = mockRequest();
      req.headers = { authorization: `Bearer ${token}` };
      const res = mockResponse();

      await authenticate(req as Request, res as Response, mockNext);

      expect(mockNext).toHaveBeenCalledWith(
        expect.objectContaining({
          code: ErrorCodes.UNAUTHORIZED,
          message: 'Token has expired'
        })
      );
    });
  });

  describe('requireEliteStatus middleware', () => {
    it('should allow Elite status users', () => {
      const req = mockRequest();
      req.user = {
        id: '123',
        email: 'test@example.com',
        statusLevel: StatusLevel.STATUS_LEVEL_ELITE
      };
      const res = mockResponse();

      requireEliteStatus(req as Request, res as Response, mockNext);

      expect(mockNext).toHaveBeenCalledWith();
    });

    it('should reject non-Elite status users', () => {
      const req = mockRequest();
      req.user = {
        id: '123',
        email: 'test@example.com',
        statusLevel: StatusLevel.STATUS_LEVEL_REGULAR
      };
      const res = mockResponse();

      requireEliteStatus(req as Request, res as Response, mockNext);

      expect(mockNext).toHaveBeenCalledWith(
        expect.objectContaining({
          code: ErrorCodes.FORBIDDEN,
          message: 'Insufficient status level'
        })
      );
    });
  });
});

describe('Validation Middleware Tests', () => {
  describe('validateSpatialData middleware', () => {
    it('should validate correct LiDAR coordinates', () => {
      const req = mockRequest();
      req.body = {
        latitude: 37.7749,
        longitude: -122.4194,
        altitude: 10,
        accuracyMeters: 0.05,
        confidence: 0.95
      };
      const res = mockResponse();

      validateSpatialData(req as Request, res as Response, mockNext);

      expect(mockNext).toHaveBeenCalledWith();
    });

    it('should reject coordinates with insufficient precision', () => {
      const req = mockRequest();
      req.body = {
        latitude: 37.7749,
        longitude: -122.4194,
        accuracyMeters: 0.2 // Too imprecise
      };
      const res = mockResponse();

      validateSpatialData(req as Request, res as Response, mockNext);

      expect(mockNext).toHaveBeenCalledWith(
        expect.objectContaining({
          code: 422,
          message: 'Location precision does not meet LiDAR requirements'
        })
      );
    });

    it('should reject invalid coordinate ranges', () => {
      const req = mockRequest();
      req.body = {
        latitude: 91, // Invalid latitude
        longitude: -122.4194
      };
      const res = mockResponse();

      validateSpatialData(req as Request, res as Response, mockNext);

      expect(mockNext).toHaveBeenCalledWith(
        expect.objectContaining({
          code: 422,
          message: 'Coordinates do not meet LiDAR precision requirements'
        })
      );
    });
  });

  describe('validateTagData middleware', () => {
    it('should validate correct tag data', () => {
      const req = mockRequest();
      req.body = {
        content: 'Test tag content',
        expiresAt: new Date(Date.now() + 86400000).toISOString(),
        visibilityRadius: 100,
        visibility: 'PUBLIC',
        mediaUrls: ['https://example.com/image.jpg'],
        existingTags: 5
      };
      const res = mockResponse();

      validateTagData(req as Request, res as Response, mockNext);

      expect(mockNext).toHaveBeenCalledWith();
    });

    it('should sanitize tag content', () => {
      const req = mockRequest();
      req.body = {
        content: '<script>alert("xss")</script>Test content',
        expiresAt: new Date(Date.now() + 86400000).toISOString(),
        visibilityRadius: 100,
        visibility: 'PUBLIC',
        existingTags: 5
      };
      const res = mockResponse();

      validateTagData(req as Request, res as Response, mockNext);

      expect(req.body.content).not.toContain('<script>');
      expect(mockNext).toHaveBeenCalledWith();
    });

    it('should reject excessive tag density', () => {
      const req = mockRequest();
      req.body = {
        content: 'Test content',
        expiresAt: new Date(Date.now() + 86400000).toISOString(),
        visibilityRadius: 10,
        visibility: 'PUBLIC',
        existingTags: 1000 // Too many tags for the area
      };
      const res = mockResponse();

      validateTagData(req as Request, res as Response, mockNext);

      expect(mockNext).toHaveBeenCalledWith(
        expect.objectContaining({
          code: 422,
          message: 'Tag density limit exceeded for the specified area'
        })
      );
    });
  });
});

describe('Error Handler Tests', () => {
  it('should format API errors correctly', () => {
    const error = {
      code: ErrorCodes.VALIDATION_ERROR,
      message: 'Validation failed',
      details: { field: 'email', error: 'Invalid format' }
    };
    const req = mockRequest();
    const res = mockResponse();

    errorHandler(error, req as Request, res as Response, mockNext);

    expect(res.status).toHaveBeenCalledWith(ErrorCodes.VALIDATION_ERROR);
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({
        success: false,
        error: expect.objectContaining({
          code: ErrorCodes.VALIDATION_ERROR,
          message: 'Validation failed'
        })
      })
    );
  });

  it('should sanitize error details in production', () => {
    const originalEnv = process.env.NODE_ENV;
    process.env.NODE_ENV = 'production';

    const error = {
      code: ErrorCodes.INTERNAL_ERROR,
      message: 'Database connection failed',
      stack: 'Error stack trace'
    };
    const req = mockRequest();
    const res = mockResponse();

    errorHandler(error, req as Request, res as Response, mockNext);

    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({
        error: expect.not.objectContaining({
          stack: expect.any(String)
        })
      })
    );

    process.env.NODE_ENV = originalEnv;
  });
});