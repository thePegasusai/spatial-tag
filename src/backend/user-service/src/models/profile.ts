// External dependencies
import { Schema, model, Document, Model, Index } from 'mongoose'; // v7.x
import { IsString, IsBoolean, ValidateNested, IsNumber, IsDate, IsOptional } from 'class-validator'; // v0.14.x

// Internal dependencies
import { Profile, Location, StatusLevel, DEFAULT_VISIBILITY_SETTINGS, LOCATION_REQUIREMENTS } from '../types';

/**
 * Interface for profile model with MongoDB document methods
 */
interface ProfileModel extends Model<Profile & Document> {
  findByUserId(userId: string): Promise<Profile | null>;
  findNearbyProfiles(center: Location, radiusInMeters: number, filters?: Record<string, any>): Promise<Profile[]>;
}

/**
 * Enhanced Mongoose schema for user profiles with spatial optimization
 */
@Schema({ timestamps: true, collection: 'profiles' })
@Index({ lastLocation: '2dsphere' })
@Index({ userId: 1 }, { unique: true })
class ProfileSchema {
  @IsString()
  userId!: string;

  @IsString()
  displayName!: string;

  @IsString()
  @IsOptional()
  bio?: string;

  @ValidateNested()
  preferences!: Record<string, any>;

  @ValidateNested()
  lastLocation!: Location;

  @ValidateNested()
  locationHistory!: Location[];

  @IsBoolean()
  isVisible!: boolean;

  @IsDate()
  lastActive!: Date;

  @IsString()
  statusLevel!: StatusLevel;

  @IsNumber()
  visibilityRadius!: number;

  @ValidateNested()
  privacySettings!: Record<string, any>;

  /**
   * Updates user's last known location with history tracking
   * @param location New location data
   */
  async updateLocation(location: Location): Promise<void> {
    // Validate location accuracy against LiDAR specifications
    if (location.accuracy > LOCATION_REQUIREMENTS.MIN_ACCURACY) {
      throw new Error('Location accuracy does not meet LiDAR requirements');
    }

    // Add to location history with timestamp
    this.locationHistory.push({
      ...location,
      timestamp: new Date()
    });

    // Maintain history size limit (keep last 100 locations)
    if (this.locationHistory.length > 100) {
      this.locationHistory = this.locationHistory.slice(-100);
    }

    // Update current location and last active timestamp
    this.lastLocation = location;
    this.lastActive = new Date();

    await this.save();
  }

  /**
   * Updates user preferences with validation
   * @param newPreferences Updated preference settings
   */
  async updatePreferences(newPreferences: Record<string, string>): Promise<void> {
    // Validate preference format
    for (const [key, value] of Object.entries(newPreferences)) {
      if (typeof value !== 'string') {
        throw new Error(`Invalid preference value for ${key}`);
      }
    }

    // Merge with existing preferences
    this.preferences = {
      ...this.preferences,
      ...newPreferences
    };

    await this.save();
  }

  /**
   * Toggles user's visibility status with radius control
   * @param visible Visibility state
   * @param radius Optional visibility radius in meters
   */
  async toggleVisibility(visible: boolean, radius?: number): Promise<void> {
    this.isVisible = visible;

    if (radius !== undefined) {
      if (radius > LOCATION_REQUIREMENTS.MAX_RANGE) {
        throw new Error(`Visibility radius cannot exceed ${LOCATION_REQUIREMENTS.MAX_RANGE}m`);
      }
      this.visibilityRadius = radius;
    }

    this.lastActive = new Date();
    await this.save();
  }
}

// Create the Mongoose schema
const profileSchema = new Schema<Profile & Document>(ProfileSchema.prototype);

// Static methods for profile queries
profileSchema.statics.findByUserId = async function(userId: string): Promise<Profile | null> {
  return this.findOne({ userId }).exec();
};

profileSchema.statics.findNearbyProfiles = async function(
  center: Location,
  radiusInMeters: number,
  filters: Record<string, any> = {}
): Promise<Profile[]> {
  // Validate radius against maximum range
  if (radiusInMeters > LOCATION_REQUIREMENTS.MAX_RANGE) {
    throw new Error(`Search radius cannot exceed ${LOCATION_REQUIREMENTS.MAX_RANGE}m`);
  }

  return this.find({
    lastLocation: {
      $near: {
        $geometry: {
          type: 'Point',
          coordinates: [center.longitude, center.latitude]
        },
        $maxDistance: radiusInMeters
      }
    },
    isVisible: true,
    ...filters
  }).exec();
};

// Create and export the model
const ProfileModel = model<Profile & Document, ProfileModel>('Profile', profileSchema);

export default ProfileModel;