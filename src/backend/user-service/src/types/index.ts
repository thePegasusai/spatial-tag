// @ts-check
import { Document } from 'mongoose'; // v7.x

/**
 * Enumeration of user status levels with progression tracking
 */
export enum StatusLevel {
  REGULAR = 'REGULAR',
  ELITE = 'ELITE',
  RARE = 'RARE'
}

/**
 * Enumeration of location data sources
 */
export enum LocationSource {
  LIDAR = 'LIDAR',
  GPS = 'GPS',
  NETWORK = 'NETWORK'
}

/**
 * High-precision location data structure
 */
export interface Location {
  latitude: number;
  longitude: number;
  accuracy: number; // in meters
  altitude: number; // in meters
  timestamp: Date;
  source: LocationSource;
}

/**
 * Notification preference settings
 */
export interface NotificationSettings {
  pushEnabled: boolean;
  emailEnabled: boolean;
  proximityAlerts: boolean;
  tagAlerts: boolean;
  statusUpdates: boolean;
}

/**
 * Privacy control settings
 */
export interface PrivacySettings {
  profileVisibility: 'public' | 'connections' | 'private';
  locationSharing: boolean;
  activityVisibility: boolean;
  statusVisibility: boolean;
}

/**
 * User preference configuration
 */
export interface UserPreferences {
  discoveryRadius: number; // in meters
  notifications: NotificationSettings;
  privacy: PrivacySettings;
}

/**
 * Device tracking information
 */
export interface DeviceInfo {
  deviceId: string;
  model: string;
  platform: string;
  osVersion: string;
  lidarCapable: boolean;
  lastSync: Date;
}

/**
 * Visibility control settings
 */
export interface VisibilitySettings {
  discoverable: boolean;
  locationVisible: boolean;
  statusVisible: boolean;
  tagsVisible: boolean;
  radiusLimit: number; // in meters
}

/**
 * Core user data interface
 */
export interface User {
  id: string;
  email: string;
  password: string; // hashed
  statusLevel: StatusLevel;
  statusPoints: number;
  lastStatusUpdate: Date;
  createdAt: Date;
  updatedAt: Date;
}

/**
 * Extended user profile data
 */
export interface Profile {
  userId: string;
  displayName: string;
  bio: string;
  preferences: UserPreferences;
  lastLocation: Location;
  locationHistory: Location[];
  isVisible: boolean;
  visibilitySettings: VisibilitySettings;
  lastActive: Date;
  deviceInfo: DeviceInfo;
}

/**
 * MongoDB document type for User with Mongoose methods
 */
export type UserDocument = User & Document;

/**
 * MongoDB document type for Profile with Mongoose methods
 */
export type ProfileDocument = Profile & Document;

/**
 * Status level thresholds
 */
export const STATUS_THRESHOLDS = {
  ELITE: 500,
  RARE: 1000
} as const;

/**
 * Location accuracy requirements
 */
export const LOCATION_REQUIREMENTS = {
  MIN_ACCURACY: 0.01, // 1cm
  MAX_RANGE: 50, // 50m
  MIN_UPDATE_INTERVAL: 1000, // 1 second
} as const;

/**
 * Default visibility settings
 */
export const DEFAULT_VISIBILITY_SETTINGS: VisibilitySettings = {
  discoverable: true,
  locationVisible: true,
  statusVisible: true,
  tagsVisible: true,
  radiusLimit: 50
} as const;

/**
 * Default user preferences
 */
export const DEFAULT_USER_PREFERENCES: UserPreferences = {
  discoveryRadius: 50,
  notifications: {
    pushEnabled: true,
    emailEnabled: true,
    proximityAlerts: true,
    tagAlerts: true,
    statusUpdates: true
  },
  privacy: {
    profileVisibility: 'public',
    locationSharing: true,
    activityVisibility: true,
    statusVisibility: true
  }
} as const;