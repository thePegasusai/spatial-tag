// @ts-check
import { describe, it, beforeEach, afterEach, beforeAll, afterAll } from 'jest'; // v29.x
import { expect } from '@jest/globals'; // v29.x
import { MongoMemoryServer } from 'mongodb-memory-server'; // v8.x
import { connect, disconnect, connection, startSession } from 'mongoose'; // v7.x

import { login, register, refreshToken, validateSession } from '../../src/services/auth';
import { UserModel } from '../../src/models/user';
import { StatusLevel } from '../../src/types';

// Test constants
const TEST_USER = {
  email: 'test@example.com',
  password: 'Test123!@#',
  firstName: 'Test',
  lastName: 'User'
};

let mongod: MongoMemoryServer;
let testSession: any;

async function setupTestDatabase() {
  mongod = await MongoMemoryServer.create();
  const uri = mongod.getUri();
  
  await connect(uri, {
    maxPoolSize: 10,
    minPoolSize: 2,
    socketTimeoutMS: 5000,
    connectTimeoutMS: 5000
  });

  await UserModel.createIndexes();
}

async function cleanupTestDatabase() {
  if (testSession) {
    await testSession.endSession();
  }
  await connection.dropDatabase();
  await connection.close();
  await mongod.stop();
}

async function setupTestTransaction() {
  testSession = await startSession();
  testSession.startTransaction();
  return testSession;
}

describe('Authentication Integration Tests', () => {
  beforeAll(async () => {
    await setupTestDatabase();
  });

  afterAll(async () => {
    await cleanupTestDatabase();
  });

  beforeEach(async () => {
    await setupTestTransaction();
  });

  afterEach(async () => {
    await testSession.abortTransaction();
    await connection.dropDatabase();
  });

  describe('User Registration', () => {
    it('should successfully register a new user', async () => {
      const response = await register(TEST_USER.email, TEST_USER.password);
      
      expect(response).toHaveProperty('accessToken');
      expect(response).toHaveProperty('refreshToken');
      expect(response).toHaveProperty('user');
      expect(response).toHaveProperty('expiresIn');
      expect(response.user.email).toBeDefined();
      expect(response.user.statusLevel).toBe(StatusLevel.REGULAR);
    });

    it('should reject duplicate email registration', async () => {
      await register(TEST_USER.email, TEST_USER.password);
      
      await expect(
        register(TEST_USER.email, TEST_USER.password)
      ).rejects.toThrow('Email already registered');
    });

    it('should reject invalid email format', async () => {
      await expect(
        register('invalid-email', TEST_USER.password)
      ).rejects.toThrow('Invalid email format');
    });

    it('should reject weak passwords', async () => {
      await expect(
        register(TEST_USER.email, 'weak')
      ).rejects.toThrow('Password must be at least 8 characters');
    });

    it('should properly hash passwords', async () => {
      await register(TEST_USER.email, TEST_USER.password);
      
      const user = await UserModel.findByEmail(TEST_USER.email);
      expect(user?.password).not.toBe(TEST_USER.password);
      expect(user?.password).toMatch(/^\$2[aby]\$\d+\$/);
    });

    it('should handle concurrent registrations', async () => {
      const promises = Array(5).fill(null).map((_, i) => 
        register(`test${i}@example.com`, TEST_USER.password)
      );
      
      const results = await Promise.allSettled(promises);
      const successful = results.filter(r => r.status === 'fulfilled');
      expect(successful).toHaveLength(5);
    });
  });

  describe('User Login', () => {
    beforeEach(async () => {
      await register(TEST_USER.email, TEST_USER.password);
    });

    it('should successfully login with valid credentials', async () => {
      const response = await login(TEST_USER.email, TEST_USER.password);
      
      expect(response).toHaveProperty('accessToken');
      expect(response).toHaveProperty('refreshToken');
      expect(response.user.email).toBeDefined();
    });

    it('should return valid access and refresh tokens', async () => {
      const response = await login(TEST_USER.email, TEST_USER.password);
      
      expect(response.accessToken).toMatch(/^[\w-]*\.[\w-]*\.[\w-]*$/);
      expect(response.refreshToken).toMatch(/^[\w-]*\.[\w-]*\.[\w-]*$/);
    });

    it('should reject invalid password', async () => {
      await expect(
        login(TEST_USER.email, 'wrongpassword')
      ).rejects.toThrow('Invalid credentials');
    });

    it('should reject non-existent user', async () => {
      await expect(
        login('nonexistent@example.com', TEST_USER.password)
      ).rejects.toThrow('Invalid credentials');
    });

    it('should respect rate limiting', async () => {
      for (let i = 0; i < 5; i++) {
        await expect(
          login(TEST_USER.email, 'wrongpassword')
        ).rejects.toThrow('Invalid credentials');
      }

      await expect(
        login(TEST_USER.email, TEST_USER.password)
      ).rejects.toThrow('Too many login attempts');
    });

    it('should track failed attempts', async () => {
      await login(TEST_USER.email, 'wrongpassword').catch(() => {});
      await login(TEST_USER.email, 'wrongpassword').catch(() => {});
      
      const response = await login(TEST_USER.email, TEST_USER.password);
      expect(response).toHaveProperty('accessToken');
    });
  });

  describe('Token Management', () => {
    let userTokens: { accessToken: string; refreshToken: string };

    beforeEach(async () => {
      const registerResponse = await register(TEST_USER.email, TEST_USER.password);
      userTokens = {
        accessToken: registerResponse.accessToken,
        refreshToken: registerResponse.refreshToken
      };
    });

    it('should successfully refresh access token', async () => {
      const response = await refreshToken(userTokens.refreshToken);
      
      expect(response).toHaveProperty('accessToken');
      expect(response).toHaveProperty('refreshToken');
      expect(response.accessToken).not.toBe(userTokens.accessToken);
    });

    it('should reject invalid refresh token', async () => {
      await expect(
        refreshToken('invalid.token.here')
      ).rejects.toThrow('Invalid refresh token');
    });

    it('should reject expired refresh token', async () => {
      // Mock Date.now to simulate token expiration
      const realNow = Date.now;
      Date.now = jest.fn(() => realNow() + 8 * 24 * 60 * 60 * 1000);
      
      await expect(
        refreshToken(userTokens.refreshToken)
      ).rejects.toThrow('Refresh token has expired');
      
      Date.now = realNow;
    });

    it('should validate token signatures', async () => {
      const response = await validateSession(userTokens.accessToken);
      expect(response).toHaveProperty('id');
      expect(response).toHaveProperty('email');
    });
  });

  describe('Session Management', () => {
    let userTokens: { accessToken: string; refreshToken: string };

    beforeEach(async () => {
      const registerResponse = await register(TEST_USER.email, TEST_USER.password);
      userTokens = {
        accessToken: registerResponse.accessToken,
        refreshToken: registerResponse.refreshToken
      };
    });

    it('should validate active session', async () => {
      const response = await validateSession(userTokens.accessToken);
      expect(response).toHaveProperty('id');
      expect(response.email).toBeDefined();
    });

    it('should reject expired access token', async () => {
      // Mock Date.now to simulate token expiration
      const realNow = Date.now;
      Date.now = jest.fn(() => realNow() + 2 * 60 * 60 * 1000);
      
      await expect(
        validateSession(userTokens.accessToken)
      ).rejects.toThrow('Invalid session');
      
      Date.now = realNow;
    });

    it('should handle session timeout', async () => {
      // Mock Date.now to simulate session timeout
      const realNow = Date.now;
      Date.now = jest.fn(() => realNow() + 4 * 60 * 60 * 1000);
      
      await expect(
        validateSession(userTokens.accessToken)
      ).rejects.toThrow('Invalid session');
      
      Date.now = realNow;
    });
  });

  describe('Security Validation', () => {
    it('should protect against brute force', async () => {
      const attempts = Array(10).fill(null).map(() => 
        login(TEST_USER.email, 'wrongpassword')
      );
      
      await Promise.all(attempts.map(p => p.catch(() => {})));
      
      await expect(
        login(TEST_USER.email, TEST_USER.password)
      ).rejects.toThrow('Too many login attempts');
    });

    it('should validate password strength', async () => {
      await expect(
        register(TEST_USER.email, 'weak')
      ).rejects.toThrow('Password must be at least 8 characters');
    });

    it('should protect sensitive data', async () => {
      const response = await register(TEST_USER.email, TEST_USER.password);
      expect(response.user).not.toHaveProperty('password');
      expect(response.user.email).not.toBe(TEST_USER.email);
    });
  });
});