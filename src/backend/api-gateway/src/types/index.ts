// @ts-version 5.0
// External imports are not needed as we're only defining types

// Import types from proto files
import { User, StatusLevel } from '../../../proto/user';
import { Tag, TagVisibility } from '../../../proto/tag';
import { Location, SpatialPoint } from '../../../proto/spatial';
import { Wishlist, CommerceItem } from '../../../proto/commerce';

/**
 * Standard API error response structure
 */
export interface APIError {
  code: number;
  message: string;
  details?: Record<string, any>;
}

/**
 * Response metadata for tracking and debugging
 */
export interface ResponseMetadata {
  timestamp: string;
  requestId: string;
  processingTime: number;
  region: string;
}

/**
 * Generic API response wrapper
 */
export interface APIResponse<T> {
  success: boolean;
  data: T | null;
  error: APIError | null;
  metadata: ResponseMetadata;
}

/**
 * Enhanced user response with location data
 */
export interface UserResponse extends Omit<User, 'lastKnownLocation'> {
  lastLocation: Location | null;
  isOnline: boolean;
  distanceMeters?: number;
  matchPercentage?: number;
}

/**
 * User preferences for the application
 */
export interface UserPreferences {
  discoveryRadius: number;
  visibilityEnabled: boolean;
  notifications: {
    pushEnabled: boolean;
    emailEnabled: boolean;
    nearbyAlerts: boolean;
    tagAlerts: boolean;
    statusAlerts: boolean;
  };
  privacy: {
    profileVisible: boolean;
    locationVisible: boolean;
    statusVisible: boolean;
    allowDiscovery: boolean;
  };
  location: {
    backgroundTracking: boolean;
    highPrecision: boolean;
    updateFrequencySeconds: number;
  };
}

/**
 * Nearby user information with distance
 */
export interface NearbyUser {
  user: UserResponse;
  distance: number;
  lastSeen: string;
  hasActiveTag: boolean;
}

/**
 * Nearby tag information with spatial data
 */
export interface NearbyTag {
  tag: Tag;
  distance: number;
  creator: UserResponse;
  isVisible: boolean;
  expiresIn: number;
}

/**
 * Proximity response containing nearby users and tags
 */
export interface ProximityResponse {
  users: NearbyUser[];
  tags: NearbyTag[];
  radius: number;
  timestamp: string;
  scanQuality: 'LOW' | 'MEDIUM' | 'HIGH' | 'ULTRA';
}

/**
 * Enhanced wishlist response with sharing features
 */
export interface WishlistResponse {
  id: string;
  userId: string;
  items: CommerceItem[];
  isShared: boolean;
  sharedWith: string[];
  collaborationSettings: {
    allowItemAddition: boolean;
    allowItemRemoval: boolean;
    allowPriceUpdates: boolean;
    notifyOnChanges: boolean;
  };
  totalValue: number;
  updatedAt: string;
}

/**
 * Error codes for different types of failures
 */
export const ErrorCodes = {
  UNAUTHORIZED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  VALIDATION_ERROR: 422,
  SPATIAL_ERROR: 460,
  TAG_ERROR: 461,
  COMMERCE_ERROR: 462,
  RATE_LIMIT_ERROR: 429,
  INTERNAL_ERROR: 500,
} as const;

/**
 * HTTP status codes used in responses
 */
export const HttpStatusCodes = {
  OK: 200,
  CREATED: 201,
  ACCEPTED: 202,
  NO_CONTENT: 204,
  BAD_REQUEST: 400,
  UNAUTHORIZED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  INTERNAL_SERVER_ERROR: 500,
} as const;

/**
 * Spatial operation types
 */
export type SpatialOperation = 
  | 'UPDATE_LOCATION'
  | 'CREATE_TAG'
  | 'INTERACT_TAG'
  | 'DISCOVER_USERS';

/**
 * Tag interaction types
 */
export type TagInteraction = 
  | 'VIEW'
  | 'LIKE'
  | 'COMMENT'
  | 'SHARE'
  | 'REPORT';

/**
 * Commerce operation types
 */
export type CommerceOperation = 
  | 'ADD_TO_WISHLIST'
  | 'REMOVE_FROM_WISHLIST'
  | 'SHARE_WISHLIST'
  | 'UPDATE_WISHLIST';

/**
 * WebSocket message types for real-time updates
 */
export type WebSocketMessageType = 
  | 'LOCATION_UPDATE'
  | 'TAG_UPDATE'
  | 'USER_UPDATE'
  | 'COMMERCE_UPDATE'
  | 'ERROR';

/**
 * WebSocket message payload
 */
export interface WebSocketMessage<T = any> {
  type: WebSocketMessageType;
  payload: T;
  timestamp: string;
  userId: string;
}

/**
 * Rate limiting configuration
 */
export interface RateLimitConfig {
  windowMs: number;
  maxRequests: number;
  statusCode: number;
  message: string;
}

/**
 * Cache configuration
 */
export interface CacheConfig {
  ttlSeconds: number;
  maxSize: number;
  checkPeriod: number;
}