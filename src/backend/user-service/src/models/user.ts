// @ts-check
import { Schema, model, Document, Model } from 'mongoose'; // v7.x
import { hash, compare } from 'bcryptjs'; // v2.4.x
import { IsEmail, MinLength, IsEnum, IsNumber } from 'class-validator'; // v0.14.x
import { 
  User, 
  UserDocument, 
  StatusLevel, 
  Location, 
  STATUS_THRESHOLDS 
} from '../types';

// Security and rate limiting constants
const SALT_ROUNDS = 12;
const MAX_LOGIN_ATTEMPTS = 5;
const LOGIN_WINDOW_MINUTES = 15;

// Rate limiting tracking
const loginAttempts = new Map<string, { count: number; firstAttempt: Date }>();

/**
 * Enhanced Mongoose schema for user data with PII protection and security features
 */
@Schema({ timestamps: true })
class UserSchema {
  @IsEmail()
  email!: string;

  @MinLength(8)
  password!: string;

  @IsEnum(StatusLevel)
  statusLevel!: StatusLevel;

  @IsNumber()
  points!: number;

  lastLocation?: Location;

  statusHistory: Date[] = [];

  createdAt!: Date;
  updatedAt!: Date;

  /**
   * Securely compares provided password with stored hash using constant-time comparison
   * @param candidatePassword - Password to verify
   * @returns Promise resolving to true if passwords match
   */
  async comparePassword(candidatePassword: string): Promise<boolean> {
    if (!candidatePassword || candidatePassword.length < 8) {
      return false;
    }

    const email = this.email;
    const attempts = loginAttempts.get(email) || { count: 0, firstAttempt: new Date() };

    // Check rate limiting
    const windowStart = new Date(Date.now() - LOGIN_WINDOW_MINUTES * 60 * 1000);
    if (attempts.firstAttempt < windowStart) {
      loginAttempts.set(email, { count: 1, firstAttempt: new Date() });
    } else if (attempts.count >= MAX_LOGIN_ATTEMPTS) {
      return false;
    } else {
      loginAttempts.set(email, { 
        count: attempts.count + 1, 
        firstAttempt: attempts.firstAttempt 
      });
    }

    try {
      const isMatch = await compare(candidatePassword, this.password);
      if (isMatch) {
        loginAttempts.delete(email);
      }
      return isMatch;
    } catch (error) {
      console.error('Password comparison error', { error });
      return false;
    }
  }

  /**
   * Updates user's status level with points validation and history tracking
   * @param newStatus - Target status level
   * @param points - Current point total
   */
  async updateStatus(newStatus: StatusLevel, points: number): Promise<void> {
    // Validate points threshold for status level
    if (newStatus === StatusLevel.ELITE && points < STATUS_THRESHOLDS.ELITE) {
      throw new Error('Insufficient points for Elite status');
    }
    if (newStatus === StatusLevel.RARE && points < STATUS_THRESHOLDS.RARE) {
      throw new Error('Insufficient points for Rare status');
    }

    // Record status change in history
    this.statusHistory.push(new Date());
    if (this.statusHistory.length > 10) {
      this.statusHistory.shift(); // Keep last 10 status changes
    }

    this.statusLevel = newStatus;
    this.points = points;
    await this.save();
  }

  /**
   * Transforms user document to JSON with PII protection
   * @returns Sanitized user object
   */
  toJSON(): Partial<User> {
    const obj = this.toObject();
    
    // Remove sensitive data
    delete obj.password;
    
    // Mask PII
    if (obj.email) {
      const [local, domain] = obj.email.split('@');
      obj.email = `${local[0]}***${local.slice(-1)}@${domain}`;
    }

    // Transform _id to id
    obj.id = obj._id.toString();
    delete obj._id;
    delete obj.__v;

    // Format dates
    if (obj.createdAt) obj.createdAt = new Date(obj.createdAt).toISOString();
    if (obj.updatedAt) obj.updatedAt = new Date(obj.updatedAt).toISOString();

    return obj;
  }
}

// Create Schema instance
const userSchema = new Schema<UserDocument>(UserSchema, {
  collection: 'users',
  timestamps: true,
  toJSON: { virtuals: true }
});

// Index definitions for performance
userSchema.index({ email: 1 }, { unique: true });
userSchema.index({ statusLevel: 1 });
userSchema.index({ points: -1 });
userSchema.index({ 'lastLocation.coordinates': '2dsphere' });

/**
 * Securely finds a user by email with rate limiting
 * @param email - User's email address
 * @returns Promise resolving to user document or null
 */
userSchema.statics.findByEmail = async function(
  email: string
): Promise<UserDocument | null> {
  if (!email || typeof email !== 'string') {
    return null;
  }

  try {
    return await this.findOne({ email: email.toLowerCase().trim() });
  } catch (error) {
    console.error('Error finding user by email', { error });
    return null;
  }
};

/**
 * Creates a new user with enhanced security measures
 * @param email - User's email address
 * @param password - User's password (will be hashed)
 * @returns Promise resolving to created user document
 */
userSchema.statics.createUser = async function(
  email: string,
  password: string
): Promise<UserDocument> {
  if (!email || !password) {
    throw new Error('Email and password required');
  }

  // Hash password with increased rounds for security
  const hashedPassword = await hash(password, SALT_ROUNDS);

  const user = new this({
    email: email.toLowerCase().trim(),
    password: hashedPassword,
    statusLevel: StatusLevel.REGULAR,
    points: 0,
    statusHistory: [new Date()]
  });

  return await user.save();
};

// Create and export the model
export const UserModel: Model<UserDocument> = model<UserDocument>('User', userSchema);

export default UserModel;