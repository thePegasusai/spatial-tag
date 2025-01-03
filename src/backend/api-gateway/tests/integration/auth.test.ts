// @ts-version 5.0

// External imports with versions
import request from 'supertest'; // v6.3.3
import { expect } from 'jest'; // v29.7.0
import { verify } from 'jsonwebtoken'; // v9.0.0
import { MockAuthService } from '@grpc/mock'; // v1.0.0
import { TestDatabase } from '@test/database'; // v1.0.0

// Internal imports
import app from '../../src/app';
import { APIError, ErrorCodes, HttpStatusCodes } from '../../src/types';
import { StatusLevel } from '../../../proto/user';

// Test configuration constants
const TEST_USERS = {
  basic: {
    email: 'basic@test.com',
    password: 'Test123!',
    status: StatusLevel.STATUS_LEVEL_REGULAR,
  },
  elite: {
    email: 'elite@test.com',
    password: 'Elite123!',
    status: StatusLevel.STATUS_LEVEL_ELITE,
  },
  rare: {
    email: 'rare@test.com',
    password: 'Rare123!',
    status: StatusLevel.STATUS_LEVEL_RARE,
  },
};

const SECURITY_CONFIG = {
  jwtSecret: 'test-secret',
  tokenExpiry: '1h',
  refreshExpiry: '7d',
  rateLimit: {
    window: 900000, // 15 minutes
    max: 100,
  },
};

describe('Authentication Integration Tests', () => {
  let mockAuthService: MockAuthService;
  let testDb: TestDatabase;

  beforeAll(async () => {
    // Initialize test database
    testDb = new TestDatabase();
    await testDb.connect();
    await testDb.loadFixtures('auth-test-fixtures');

    // Initialize mock gRPC auth service
    mockAuthService = new MockAuthService();
    await mockAuthService.start();

    // Configure test environment
    process.env.JWT_SECRET = SECURITY_CONFIG.jwtSecret;
    process.env.TOKEN_EXPIRY = SECURITY_CONFIG.tokenExpiry;
    process.env.RATE_LIMIT_WINDOW = String(SECURITY_CONFIG.rateLimit.window);
    process.env.RATE_LIMIT_MAX = String(SECURITY_CONFIG.rateLimit.max);
  });

  afterAll(async () => {
    await testDb.disconnect();
    await mockAuthService.stop();
  });

  describe('OAuth Authentication Flow', () => {
    it('should successfully authenticate with Apple OAuth', async () => {
      const mockAppleToken = 'mock-apple-token';
      const response = await request(app)
        .post('/api/auth/oauth/apple')
        .send({ token: mockAppleToken })
        .expect(HttpStatusCodes.OK);

      expect(response.body.success).toBe(true);
      expect(response.body.data).toHaveProperty('accessToken');
      expect(response.body.data).toHaveProperty('refreshToken');

      // Verify JWT token
      const decoded = verify(response.body.data.accessToken, SECURITY_CONFIG.jwtSecret);
      expect(decoded).toHaveProperty('userId');
      expect(decoded).toHaveProperty('statusLevel');
    });

    it('should handle invalid OAuth tokens', async () => {
      const response = await request(app)
        .post('/api/auth/oauth/apple')
        .send({ token: 'invalid-token' })
        .expect(HttpStatusCodes.UNAUTHORIZED);

      expect(response.body.success).toBe(false);
      expect(response.body.error.code).toBe(ErrorCodes.UNAUTHORIZED);
    });
  });

  describe('Email Authentication Flow', () => {
    it('should successfully authenticate with valid credentials', async () => {
      const response = await request(app)
        .post('/api/auth/login')
        .send({
          email: TEST_USERS.basic.email,
          password: TEST_USERS.basic.password,
        })
        .expect(HttpStatusCodes.OK);

      expect(response.body.success).toBe(true);
      expect(response.body.data).toHaveProperty('accessToken');
      expect(response.body.data).toHaveProperty('refreshToken');

      // Verify security headers
      expect(response.headers['strict-transport-security']).toBeDefined();
      expect(response.headers['x-content-type-options']).toBe('nosniff');
      expect(response.headers['x-frame-options']).toBe('DENY');
      expect(response.headers['x-xss-protection']).toBe('1; mode=block');
    });

    it('should handle invalid credentials', async () => {
      const response = await request(app)
        .post('/api/auth/login')
        .send({
          email: TEST_USERS.basic.email,
          password: 'wrong-password',
        })
        .expect(HttpStatusCodes.UNAUTHORIZED);

      expect(response.body.success).toBe(false);
      expect(response.body.error.code).toBe(ErrorCodes.UNAUTHORIZED);
    });

    it('should enforce rate limiting', async () => {
      const attempts = Array(SECURITY_CONFIG.rateLimit.max + 1).fill(null);
      
      for (const _ of attempts) {
        const response = await request(app)
          .post('/api/auth/login')
          .send({
            email: TEST_USERS.basic.email,
            password: 'wrong-password',
          });

        if (response.status === HttpStatusCodes.TOO_MANY_REQUESTS) {
          expect(response.body.error.code).toBe(ErrorCodes.RATE_LIMITED);
          break;
        }
      }
    });
  });

  describe('Token Management', () => {
    let validAccessToken: string;
    let validRefreshToken: string;

    beforeEach(async () => {
      const response = await request(app)
        .post('/api/auth/login')
        .send({
          email: TEST_USERS.basic.email,
          password: TEST_USERS.basic.password,
        });

      validAccessToken = response.body.data.accessToken;
      validRefreshToken = response.body.data.refreshToken;
    });

    it('should successfully refresh access token', async () => {
      const response = await request(app)
        .post('/api/auth/refresh')
        .send({ refreshToken: validRefreshToken })
        .expect(HttpStatusCodes.OK);

      expect(response.body.success).toBe(true);
      expect(response.body.data).toHaveProperty('accessToken');
      expect(response.body.data.accessToken).not.toBe(validAccessToken);
    });

    it('should handle expired tokens', async () => {
      // Wait for token to expire
      await new Promise(resolve => setTimeout(resolve, 100));
      
      const expiredToken = 'expired.token.signature';
      const response = await request(app)
        .get('/api/protected-route')
        .set('Authorization', `Bearer ${expiredToken}`)
        .expect(HttpStatusCodes.UNAUTHORIZED);

      expect(response.body.error.code).toBe(ErrorCodes.UNAUTHORIZED);
      expect(response.body.error.message).toContain('expired');
    });
  });

  describe('Authorization Levels', () => {
    it('should enforce Elite status requirements', async () => {
      const basicUserToken = await getTokenForUser(TEST_USERS.basic);
      const eliteUserToken = await getTokenForUser(TEST_USERS.elite);

      // Basic user attempt
      const basicResponse = await request(app)
        .get('/api/elite-feature')
        .set('Authorization', `Bearer ${basicUserToken}`)
        .expect(HttpStatusCodes.FORBIDDEN);

      expect(basicResponse.body.error.code).toBe(ErrorCodes.FORBIDDEN);

      // Elite user attempt
      const eliteResponse = await request(app)
        .get('/api/elite-feature')
        .set('Authorization', `Bearer ${eliteUserToken}`)
        .expect(HttpStatusCodes.OK);

      expect(eliteResponse.body.success).toBe(true);
    });

    it('should enforce Rare status requirements', async () => {
      const eliteUserToken = await getTokenForUser(TEST_USERS.elite);
      const rareUserToken = await getTokenForUser(TEST_USERS.rare);

      // Elite user attempt
      const eliteResponse = await request(app)
        .get('/api/rare-feature')
        .set('Authorization', `Bearer ${eliteUserToken}`)
        .expect(HttpStatusCodes.FORBIDDEN);

      expect(eliteResponse.body.error.code).toBe(ErrorCodes.FORBIDDEN);

      // Rare user attempt
      const rareResponse = await request(app)
        .get('/api/rare-feature')
        .set('Authorization', `Bearer ${rareUserToken}`)
        .expect(HttpStatusCodes.OK);

      expect(rareResponse.body.success).toBe(true);
    });
  });
});

// Helper function to get auth token for test user
async function getTokenForUser(user: typeof TEST_USERS.basic): Promise<string> {
  const response = await request(app)
    .post('/api/auth/login')
    .send({
      email: user.email,
      password: user.password,
    });

  return response.body.data.accessToken;
}