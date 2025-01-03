import Redis from 'ioredis'; // v5.x
import dayjs from 'dayjs'; // v1.x
import winston from 'winston'; // v3.x
import { UserModel } from '../models/user';
import { StatusLevel, UserDocument, ActivityType } from '../types';

// Constants for points management
const POINTS_EXPIRY_DAYS = 7;
const POINTS_KEY_PREFIX = 'user:points:';
const ACTIVITY_POINTS = {
  TAG_CREATION: 10,
  INTERACTION: 5,
  PURCHASE: 20
} as const;

// Rate limiting constants
const RATE_LIMIT_WINDOW = 3600; // 1 hour in seconds
const MAX_POINTS_PER_HOUR = 1000;
const STATUS_TRANSITION_COOLDOWN = 86400; // 24 hours in seconds

// Initialize Redis client
const redis = new Redis({
  host: process.env.REDIS_HOST || 'localhost',
  port: Number(process.env.REDIS_PORT) || 6379,
  retryStrategy: (times) => Math.min(times * 50, 2000),
});

// Initialize logger
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.json(),
  transports: [
    new winston.transports.File({ filename: 'status-service-error.log', level: 'error' }),
    new winston.transports.File({ filename: 'status-service-combined.log' })
  ]
});

/**
 * Service for managing user status calculations and updates
 */
export const StatusService = {
  /**
   * Calculates total points earned by user in current week
   * @param userId - User's unique identifier
   * @returns Promise resolving to total points
   */
  async calculateWeeklyPoints(userId: string): Promise<number> {
    try {
      const weekNumber = dayjs().week();
      const pointsKey = `${POINTS_KEY_PREFIX}${userId}:${weekNumber}`;

      const pipeline = redis.pipeline();
      
      // Get points for each activity type
      pipeline.get(`${pointsKey}:tag`);
      pipeline.get(`${pointsKey}:interaction`);
      pipeline.get(`${pointsKey}:purchase`);

      const results = await pipeline.exec();
      if (!results) {
        throw new Error('Failed to execute Redis pipeline');
      }

      // Aggregate points from all activities
      const totalPoints = results.reduce((sum, [err, points]) => {
        if (err) {
          logger.error('Error retrieving points', { error: err, userId });
          return sum;
        }
        return sum + (Number(points) || 0);
      }, 0);

      logger.info('Weekly points calculated', { userId, totalPoints, weekNumber });
      return totalPoints;
    } catch (error) {
      logger.error('Error calculating weekly points', { error, userId });
      throw error;
    }
  },

  /**
   * Determines appropriate status level based on points
   * @param points - Current point total
   * @param currentStatus - User's current status level
   * @returns Calculated status level
   */
  async determineStatusLevel(points: number, currentStatus: StatusLevel): Promise<StatusLevel> {
    if (points < 0) {
      throw new Error('Points cannot be negative');
    }

    // Check cooldown period for status transitions
    const lastTransitionKey = `${POINTS_KEY_PREFIX}${currentStatus}:last_transition`;
    const lastTransition = await redis.get(lastTransitionKey);
    
    if (lastTransition && Date.now() - Number(lastTransition) < STATUS_TRANSITION_COOLDOWN * 1000) {
      return currentStatus;
    }

    let newStatus = StatusLevel.REGULAR;
    
    if (points > 1000) {
      newStatus = StatusLevel.RARE;
    } else if (points > 500) {
      newStatus = StatusLevel.ELITE;
    }

    if (newStatus !== currentStatus) {
      await redis.set(lastTransitionKey, Date.now());
    }

    logger.info('Status level determined', { points, currentStatus, newStatus });
    return newStatus;
  },

  /**
   * Updates user's status based on weekly points
   * @param userId - User's unique identifier
   */
  async updateUserStatus(userId: string): Promise<void> {
    const session = await UserModel.startSession();
    
    try {
      await session.withTransaction(async () => {
        const weeklyPoints = await this.calculateWeeklyPoints(userId);
        const user = await UserModel.findById(userId).session(session);
        
        if (!user) {
          throw new Error('User not found');
        }

        const newStatus = await this.determineStatusLevel(weeklyPoints, user.statusLevel);
        
        if (newStatus !== user.statusLevel) {
          await user.updateStatus(newStatus, weeklyPoints);
          logger.info('User status updated', { userId, oldStatus: user.statusLevel, newStatus });
        }
      });
    } catch (error) {
      logger.error('Error updating user status', { error, userId });
      throw error;
    } finally {
      session.endSession();
    }
  },

  /**
   * Adds points for a specific activity type
   * @param userId - User's unique identifier
   * @param activityType - Type of activity generating points
   */
  async addPoints(userId: string, activityType: ActivityType): Promise<void> {
    try {
      const weekNumber = dayjs().week();
      const pointsKey = `${POINTS_KEY_PREFIX}${userId}:${weekNumber}`;
      const rateLimitKey = `${pointsKey}:rate_limit`;

      // Check rate limiting
      const hourlyPoints = await redis.get(rateLimitKey) || '0';
      if (Number(hourlyPoints) >= MAX_POINTS_PER_HOUR) {
        throw new Error('Points rate limit exceeded');
      }

      // Determine points for activity
      let points = 0;
      switch (activityType) {
        case 'TAG_CREATION':
          points = ACTIVITY_POINTS.TAG_CREATION;
          break;
        case 'INTERACTION':
          points = ACTIVITY_POINTS.INTERACTION;
          break;
        case 'PURCHASE':
          points = ACTIVITY_POINTS.PURCHASE;
          break;
        default:
          throw new Error('Invalid activity type');
      }

      const pipeline = redis.pipeline();
      
      // Add points with expiration
      pipeline.incrby(`${pointsKey}:${activityType.toLowerCase()}`, points);
      pipeline.expire(`${pointsKey}:${activityType.toLowerCase()}`, POINTS_EXPIRY_DAYS * 86400);
      
      // Update rate limiting
      pipeline.incrby(rateLimitKey, points);
      pipeline.expire(rateLimitKey, RATE_LIMIT_WINDOW);

      await pipeline.exec();

      // Check if status update is needed
      const totalPoints = await this.calculateWeeklyPoints(userId);
      if (totalPoints >= 500 || totalPoints >= 1000) {
        await this.updateUserStatus(userId);
      }

      logger.info('Points added successfully', { userId, activityType, points });
    } catch (error) {
      logger.error('Error adding points', { error, userId, activityType });
      throw error;
    }
  }
};

export default StatusService;