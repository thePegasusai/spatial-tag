import Redis from 'ioredis'; // v5.x
import { Logger } from 'winston'; // v3.x
import { Profile, Location, PrivacySettings, StatusLevel } from '../types';
import ProfileModel from '../models/profile';
import StatusService from './status';

// Constants for profile management
const CACHE_TTL = 300; // 5 minutes
const MAX_RADIUS_METERS = 50;
const MIN_LIDAR_ACCURACY = 0.95;
const LOCATION_UPDATE_THRESHOLD_METERS = 5;
const CACHE_CLUSTER_SIZE = 3;
const PRIVACY_LEVELS = {
  HIGH: 3,
  MEDIUM: 2,
  LOW: 1
} as const;

/**
 * Enhanced service class for managing user profile operations with LiDAR support
 */
export class ProfileService {
  private redisClient: Redis;
  private statusService: typeof StatusService;
  private logger: Logger;

  constructor(redisClient: Redis, statusService: typeof StatusService, logger: Logger) {
    this.redisClient = redisClient;
    this.statusService = statusService;
    this.logger = logger;
  }

  /**
   * Retrieves user profile with enhanced privacy controls
   * @param userId - Target user identifier
   * @param requestorPrivacy - Privacy settings of requesting user
   * @returns Promise resolving to privacy-filtered profile
   */
  async getProfile(userId: string, requestorPrivacy?: PrivacySettings): Promise<Profile | null> {
    try {
      // Check cache first
      const cachedProfile = await this.redisClient.get(`profile:${userId}`);
      if (cachedProfile) {
        const profile = JSON.parse(cachedProfile);
        return this.applyPrivacyFilters(profile, requestorPrivacy);
      }

      // Fetch from database if cache miss
      const profile = await ProfileModel.findByUserId(userId);
      if (!profile) {
        return null;
      }

      // Cache profile with TTL
      await this.redisClient.setex(
        `profile:${userId}`,
        CACHE_TTL,
        JSON.stringify(profile)
      );

      return this.applyPrivacyFilters(profile, requestorPrivacy);
    } catch (error) {
      this.logger.error('Error retrieving profile', { error, userId });
      throw error;
    }
  }

  /**
   * Updates user location with LiDAR accuracy validation
   * @param userId - User identifier
   * @param location - New location data
   * @param lidarData - LiDAR sensor data
   */
  async updateLocation(
    userId: string,
    location: Location,
    lidarData: { accuracy: number; confidence: number }
  ): Promise<void> {
    try {
      // Validate LiDAR accuracy
      if (lidarData.accuracy < MIN_LIDAR_ACCURACY) {
        throw new Error('LiDAR accuracy below minimum threshold');
      }

      const profile = await ProfileModel.findByUserId(userId);
      if (!profile) {
        throw new Error('Profile not found');
      }

      // Calculate distance from last location
      const distanceChanged = this.calculateDistance(
        profile.lastLocation,
        location
      );

      // Only update if significant movement detected
      if (distanceChanged >= LOCATION_UPDATE_THRESHOLD_METERS) {
        await profile.updateLocation(location);

        // Invalidate cached profile
        await this.redisClient.del(`profile:${userId}`);

        // Record location update activity
        await this.statusService.recordActivity(userId, 'LOCATION_UPDATE');

        // Update spatial index
        await this.updateSpatialIndex(userId, location);

        this.logger.info('Location updated successfully', {
          userId,
          distance: distanceChanged
        });
      }
    } catch (error) {
      this.logger.error('Error updating location', { error, userId });
      throw error;
    }
  }

  /**
   * Discovers nearby users with enhanced spatial optimization
   * @param center - Search center location
   * @param radiusInMeters - Search radius
   * @param privacyFilter - Privacy filter settings
   * @returns Promise resolving to filtered nearby profiles
   */
  async findNearbyUsers(
    center: Location,
    radiusInMeters: number,
    privacyFilter?: PrivacySettings
  ): Promise<Profile[]> {
    try {
      // Validate search radius
      if (radiusInMeters > MAX_RADIUS_METERS) {
        throw new Error(`Search radius cannot exceed ${MAX_RADIUS_METERS}m`);
      }

      // Query spatial index for nearby profiles
      const nearbyProfiles = await ProfileModel.findNearbyProfiles(
        center,
        radiusInMeters,
        { isVisible: true }
      );

      // Apply privacy filters and distance-based rules
      const filteredProfiles = nearbyProfiles
        .map(profile => this.applyPrivacyFilters(profile, privacyFilter))
        .filter(profile => profile !== null) as Profile[];

      return this.applyDistanceBasedPrivacy(filteredProfiles, center);
    } catch (error) {
      this.logger.error('Error finding nearby users', { error });
      throw error;
    }
  }

  /**
   * Applies privacy filters based on settings
   * @private
   */
  private applyPrivacyFilters(
    profile: Profile,
    requestorPrivacy?: PrivacySettings
  ): Profile | null {
    if (!profile.isVisible) {
      return null;
    }

    const privacyLevel = this.calculatePrivacyLevel(profile, requestorPrivacy);
    const filteredProfile = { ...profile };

    if (privacyLevel >= PRIVACY_LEVELS.HIGH) {
      delete filteredProfile.locationHistory;
      delete filteredProfile.deviceInfo;
    }

    if (privacyLevel >= PRIVACY_LEVELS.MEDIUM) {
      delete filteredProfile.preferences;
      filteredProfile.lastLocation = this.fuzzyLocation(profile.lastLocation);
    }

    return filteredProfile;
  }

  /**
   * Updates spatial index for efficient queries
   * @private
   */
  private async updateSpatialIndex(
    userId: string,
    location: Location
  ): Promise<void> {
    const spatialKey = `spatial:${userId}`;
    await this.redisClient
      .pipeline()
      .geoadd(
        'user_locations',
        location.longitude,
        location.latitude,
        spatialKey
      )
      .expire(spatialKey, CACHE_TTL)
      .exec();
  }

  /**
   * Calculates distance between two locations
   * @private
   */
  private calculateDistance(loc1: Location, loc2: Location): number {
    const R = 6371e3; // Earth's radius in meters
    const φ1 = (loc1.latitude * Math.PI) / 180;
    const φ2 = (loc2.latitude * Math.PI) / 180;
    const Δφ = ((loc2.latitude - loc1.latitude) * Math.PI) / 180;
    const Δλ = ((loc2.longitude - loc1.longitude) * Math.PI) / 180;

    const a =
      Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
      Math.cos(φ1) * Math.cos(φ2) * Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

    return R * c;
  }

  /**
   * Applies distance-based privacy rules
   * @private
   */
  private applyDistanceBasedPrivacy(
    profiles: Profile[],
    center: Location
  ): Profile[] {
    return profiles.map(profile => {
      const distance = this.calculateDistance(center, profile.lastLocation);
      const privacyLevel = Math.floor(distance / 10); // Increase privacy with distance

      return this.applyPrivacyFilters(profile, {
        profileVisibility: privacyLevel > 2 ? 'private' : 'public',
        locationSharing: privacyLevel <= 1,
        activityVisibility: privacyLevel <= 2,
        statusVisibility: true
      });
    }).filter((profile): profile is Profile => profile !== null);
  }

  /**
   * Calculates privacy level based on settings
   * @private
   */
  private calculatePrivacyLevel(
    profile: Profile,
    requestorPrivacy?: PrivacySettings
  ): number {
    let level = PRIVACY_LEVELS.LOW;

    if (profile.visibilitySettings.profileVisibility === 'private') {
      level = PRIVACY_LEVELS.HIGH;
    } else if (profile.visibilitySettings.profileVisibility === 'connections') {
      level = PRIVACY_LEVELS.MEDIUM;
    }

    if (requestorPrivacy?.profileVisibility === 'private') {
      level = Math.max(level, PRIVACY_LEVELS.MEDIUM);
    }

    return level;
  }

  /**
   * Adds fuzzing to location data for privacy
   * @private
   */
  private fuzzyLocation(location: Location): Location {
    const fuzzFactor = 0.0001; // Approximately 10m at equator
    return {
      ...location,
      latitude: location.latitude + (Math.random() - 0.5) * fuzzFactor,
      longitude: location.longitude + (Math.random() - 0.5) * fuzzFactor,
      accuracy: Math.max(location.accuracy, 10) // Minimum 10m accuracy for privacy
    };
  }
}

export default ProfileService;