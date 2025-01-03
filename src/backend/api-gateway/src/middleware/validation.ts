import { Request, Response, NextFunction, RequestHandler } from 'express';
import Ajv, { JSONSchemaType, ValidateFunction } from 'ajv';
import addFormats from 'ajv-formats';
import xss from 'xss';
import NodeCache from 'node-cache';
import { APIError } from '../types';

// Initialize AJV with all formats and strict mode
const ajv = new Ajv({
  allErrors: true,
  removeAdditional: true,
  useDefaults: true,
  coerceTypes: true,
  strict: true
});
addFormats(ajv);

// Initialize validation cache
const validationCache = new NodeCache({
  stdTTL: 3600, // 1 hour cache
  checkperiod: 120,
  maxKeys: 100
});

// Validation schemas for different data types
const VALIDATION_SCHEMAS = {
  USER_SCHEMA: {
    type: 'object',
    properties: {
      email: { type: 'string', format: 'email' },
      displayName: { type: 'string', minLength: 2, maxLength: 50 },
      statusLevel: { type: 'string', enum: ['REGULAR', 'ELITE', 'RARE'] },
      preferences: {
        type: 'object',
        properties: {
          discoveryRadius: { type: 'number', minimum: 0, maximum: 5000 },
          visibilityEnabled: { type: 'boolean' }
        }
      }
    },
    required: ['email']
  } as JSONSchemaType<any>,

  SPATIAL_SCHEMA: {
    type: 'object',
    properties: {
      latitude: { type: 'number', minimum: -90, maximum: 90 },
      longitude: { type: 'number', minimum: -180, maximum: 180 },
      altitude: { type: 'number', nullable: true },
      accuracyMeters: { type: 'number', minimum: 0, maximum: 100 },
      confidence: { type: 'number', minimum: 0, maximum: 1 }
    },
    required: ['latitude', 'longitude']
  } as JSONSchemaType<any>,

  TAG_SCHEMA: {
    type: 'object',
    properties: {
      content: { type: 'string', maxLength: 1000 },
      expiresAt: { type: 'string', format: 'date-time' },
      visibilityRadius: { type: 'number', minimum: 1, maximum: 1000 },
      visibility: { type: 'string', enum: ['PUBLIC', 'PRIVATE', 'ELITE_ONLY', 'RARE_ONLY'] },
      mediaUrls: { 
        type: 'array', 
        items: { type: 'string', format: 'uri' },
        maxItems: 5
      }
    },
    required: ['content', 'expiresAt', 'visibilityRadius', 'visibility']
  } as JSONSchemaType<any>
};

// Validation error messages
const VALIDATION_MESSAGES = {
  INVALID_EMAIL: 'Invalid email format or domain',
  INVALID_PASSWORD: 'Password does not meet security requirements',
  INVALID_COORDINATES: 'Coordinates do not meet LiDAR precision requirements',
  INVALID_TAG_CONTENT: 'Invalid tag content or media format',
  INVALID_STATUS_PRIVILEGE: 'Insufficient status level for operation',
  RATE_LIMIT_EXCEEDED: 'Validation attempt rate limit exceeded'
};

// Validation limits
const VALIDATION_LIMITS = {
  MAX_TAG_DENSITY: 10, // tags per square meter
  MAX_DISCOVERY_RADIUS: 5000, // meters
  MAX_CONTENT_SIZE: 1048576, // 1MB in bytes
  RATE_LIMIT_WINDOW: 60000 // 1 minute in milliseconds
};

/**
 * Creates a validation middleware function for a given JSON schema
 */
export const validateSchema = (schema: JSONSchemaType<any>, options: any = {}): RequestHandler => {
  const cacheKey = JSON.stringify(schema);
  let validate: ValidateFunction = validationCache.get(cacheKey);

  if (!validate) {
    validate = ajv.compile(schema);
    validationCache.set(cacheKey, validate);
  }

  return (req: Request, res: Response, next: NextFunction): void => {
    const valid = validate(req.body);

    if (!valid) {
      const error: APIError = {
        code: 422,
        message: 'Validation failed',
        details: validate.errors
      };
      next(error);
      return;
    }

    next();
  };
};

/**
 * Validates user-related request data with enhanced security checks
 */
export const validateUserInput = (req: Request, res: Response, next: NextFunction): void => {
  try {
    // Sanitize user input
    const sanitizedBody = Object.entries(req.body).reduce((acc, [key, value]) => ({
      ...acc,
      [key]: typeof value === 'string' ? xss(value as string) : value
    }), {});

    req.body = sanitizedBody;

    // Validate against user schema
    const validate = ajv.compile(VALIDATION_SCHEMAS.USER_SCHEMA);
    if (!validate(req.body)) {
      throw {
        code: 422,
        message: 'User validation failed',
        details: validate.errors
      };
    }

    next();
  } catch (error) {
    next(error);
  }
};

/**
 * Validates spatial and location data with LiDAR precision requirements
 */
export const validateSpatialData = (req: Request, res: Response, next: NextFunction): void => {
  try {
    const validate = ajv.compile(VALIDATION_SCHEMAS.SPATIAL_SCHEMA);
    
    if (!validate(req.body)) {
      throw {
        code: 422,
        message: VALIDATION_MESSAGES.INVALID_COORDINATES,
        details: validate.errors
      };
    }

    // Additional LiDAR-specific validations
    if (req.body.accuracyMeters > 0.1) { // 10cm precision requirement
      throw {
        code: 422,
        message: 'Location precision does not meet LiDAR requirements'
      };
    }

    next();
  } catch (error) {
    next(error);
  }
};

/**
 * Validates tag creation and update requests with rich media support
 */
export const validateTagData = (req: Request, res: Response, next: NextFunction): void => {
  try {
    // Sanitize tag content
    if (req.body.content) {
      req.body.content = xss(req.body.content);
    }

    const validate = ajv.compile(VALIDATION_SCHEMAS.TAG_SCHEMA);
    
    if (!validate(req.body)) {
      throw {
        code: 422,
        message: VALIDATION_MESSAGES.INVALID_TAG_CONTENT,
        details: validate.errors
      };
    }

    // Validate tag density
    if (req.body.visibilityRadius) {
      const area = Math.PI * Math.pow(req.body.visibilityRadius, 2);
      const maxTags = Math.floor(area * VALIDATION_LIMITS.MAX_TAG_DENSITY);
      
      if (req.body.existingTags > maxTags) {
        throw {
          code: 422,
          message: 'Tag density limit exceeded for the specified area'
        };
      }
    }

    next();
  } catch (error) {
    next(error);
  }
};

export default {
  validateSchema,
  validateUserInput,
  validateSpatialData,
  validateTagData
};