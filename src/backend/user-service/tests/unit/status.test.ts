import { jest } from '@jest/globals';
import Redis from 'ioredis-mock';
import dayjs from 'dayjs'; // v1.x
import winston from 'winston'; // v3.x
import { StatusService } from '../../src/services/status';
import { StatusLevel } from '../../src/types';
import { UserModel } from '../../src/models/user';

// Constants for testing
const TEST_USER_ID = 'test-user-123';
const POINTS_KEY_PREFIX = 'user:points:';
const MOCK_WEEK_NUMBER = 25;

// Mock Redis client
jest.mock('ioredis', () => require('ioredis-mock'));

// Mock Winston logger
jest.mock('winston', () => ({
  createLogger: jest.fn(() => ({
    info: jest.fn(),
    error: jest.fn()
  })),
  format: {
    json: jest.fn()
  },
  transports: {
    File: jest.fn()
  }
}));

// Mock UserModel
jest.mock('../../src/models/user', () => ({
  UserModel: {
    findById: jest.fn(),
    startSession: jest.fn(() => ({
      withTransaction: jest.fn(callback => callback()),
      endSession: jest.fn()
    }))
  }
}));

describe('StatusService', () => {
  let redis: Redis;
  
  beforeEach(() => {
    // Reset all mocks
    jest.clearAllMocks();
    redis = new Redis();
    
    // Mock dayjs week number
    jest.spyOn(dayjs.prototype, 'week').mockReturnValue(MOCK_WEEK_NUMBER);
    
    // Mock user model response
    (UserModel.findById as jest.Mock).mockResolvedValue({
      statusLevel: StatusLevel.REGULAR,
      updateStatus: jest.fn()
    });
  });

  afterEach(async () => {
    await redis.flushall();
  });

  describe('calculateWeeklyPoints', () => {
    it('should correctly calculate total points from all activities', async () => {
      // Set up test data
      const pointsKey = `${POINTS_KEY_PREFIX}${TEST_USER_ID}:${MOCK_WEEK_NUMBER}`;
      await redis.multi()
        .set(`${pointsKey}:tag`, '30') // 3 tag creations
        .set(`${pointsKey}:interaction`, '25') // 5 interactions
        .set(`${pointsKey}:purchase`, '40') // 2 purchases
        .exec();

      const totalPoints = await StatusService.calculateWeeklyPoints(TEST_USER_ID);
      expect(totalPoints).toBe(95);
    });

    it('should handle missing activity points', async () => {
      const totalPoints = await StatusService.calculateWeeklyPoints(TEST_USER_ID);
      expect(totalPoints).toBe(0);
    });

    it('should handle Redis errors gracefully', async () => {
      jest.spyOn(redis, 'pipeline').mockImplementationOnce(() => {
        throw new Error('Redis connection error');
      });

      await expect(StatusService.calculateWeeklyPoints(TEST_USER_ID))
        .rejects.toThrow('Redis connection error');
    });
  });

  describe('determineStatusLevel', () => {
    it('should determine REGULAR status for < 500 points', async () => {
      const status = await StatusService.determineStatusLevel(400, StatusLevel.REGULAR);
      expect(status).toBe(StatusLevel.REGULAR);
    });

    it('should determine ELITE status for >= 500 points', async () => {
      const status = await StatusService.determineStatusLevel(600, StatusLevel.REGULAR);
      expect(status).toBe(StatusLevel.ELITE);
    });

    it('should determine RARE status for >= 1000 points', async () => {
      const status = await StatusService.determineStatusLevel(1200, StatusLevel.ELITE);
      expect(status).toBe(StatusLevel.RARE);
    });

    it('should respect status transition cooldown period', async () => {
      const lastTransitionKey = `${POINTS_KEY_PREFIX}${StatusLevel.REGULAR}:last_transition`;
      await redis.set(lastTransitionKey, Date.now().toString());

      const status = await StatusService.determineStatusLevel(600, StatusLevel.REGULAR);
      expect(status).toBe(StatusLevel.REGULAR);
    });

    it('should reject negative points', async () => {
      await expect(StatusService.determineStatusLevel(-100, StatusLevel.REGULAR))
        .rejects.toThrow('Points cannot be negative');
    });
  });

  describe('updateUserStatus', () => {
    it('should update user status when points threshold is met', async () => {
      const mockUser = {
        statusLevel: StatusLevel.REGULAR,
        updateStatus: jest.fn()
      };
      (UserModel.findById as jest.Mock).mockResolvedValue(mockUser);

      // Mock 600 points for ELITE status
      jest.spyOn(StatusService, 'calculateWeeklyPoints').mockResolvedValue(600);

      await StatusService.updateUserStatus(TEST_USER_ID);

      expect(mockUser.updateStatus).toHaveBeenCalledWith(StatusLevel.ELITE, 600);
    });

    it('should not update status when points are insufficient', async () => {
      const mockUser = {
        statusLevel: StatusLevel.REGULAR,
        updateStatus: jest.fn()
      };
      (UserModel.findById as jest.Mock).mockResolvedValue(mockUser);

      jest.spyOn(StatusService, 'calculateWeeklyPoints').mockResolvedValue(400);

      await StatusService.updateUserStatus(TEST_USER_ID);

      expect(mockUser.updateStatus).not.toHaveBeenCalled();
    });

    it('should handle non-existent user', async () => {
      (UserModel.findById as jest.Mock).mockResolvedValue(null);

      await expect(StatusService.updateUserStatus(TEST_USER_ID))
        .rejects.toThrow('User not found');
    });
  });

  describe('addPoints', () => {
    it('should add points for tag creation', async () => {
      await StatusService.addPoints(TEST_USER_ID, 'TAG_CREATION');

      const points = await redis.get(
        `${POINTS_KEY_PREFIX}${TEST_USER_ID}:${MOCK_WEEK_NUMBER}:tag`
      );
      expect(Number(points)).toBe(10);
    });

    it('should add points for interaction', async () => {
      await StatusService.addPoints(TEST_USER_ID, 'INTERACTION');

      const points = await redis.get(
        `${POINTS_KEY_PREFIX}${TEST_USER_ID}:${MOCK_WEEK_NUMBER}:interaction`
      );
      expect(Number(points)).toBe(5);
    });

    it('should add points for purchase', async () => {
      await StatusService.addPoints(TEST_USER_ID, 'PURCHASE');

      const points = await redis.get(
        `${POINTS_KEY_PREFIX}${TEST_USER_ID}:${MOCK_WEEK_NUMBER}:purchase`
      );
      expect(Number(points)).toBe(20);
    });

    it('should enforce rate limiting', async () => {
      const rateLimitKey = `${POINTS_KEY_PREFIX}${TEST_USER_ID}:${MOCK_WEEK_NUMBER}:rate_limit`;
      await redis.set(rateLimitKey, '1000'); // Max points per hour

      await expect(StatusService.addPoints(TEST_USER_ID, 'TAG_CREATION'))
        .rejects.toThrow('Points rate limit exceeded');
    });

    it('should trigger status update at threshold', async () => {
      jest.spyOn(StatusService, 'calculateWeeklyPoints').mockResolvedValue(500);
      jest.spyOn(StatusService, 'updateUserStatus');

      await StatusService.addPoints(TEST_USER_ID, 'PURCHASE');

      expect(StatusService.updateUserStatus).toHaveBeenCalledWith(TEST_USER_ID);
    });

    it('should handle invalid activity type', async () => {
      await expect(StatusService.addPoints(TEST_USER_ID, 'INVALID' as any))
        .rejects.toThrow('Invalid activity type');
    });
  });
});