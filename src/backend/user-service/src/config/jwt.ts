// @ts-check
import { sign, verify, JwtPayload } from 'jsonwebtoken'; // v9.0.0
import { UnauthorizedError } from '@hapi/boom'; // v10.0.1
import { User, StatusLevel } from '../types';
import { randomBytes } from 'crypto';

// Environment configuration with strict validation
const JWT_SECRET = process.env.JWT_SECRET || (
  process.env.NODE_ENV === 'production' 
    ? (() => { throw new Error('JWT_SECRET must be set in production') })() 
    : 'your-256-bit-secret'
);

const JWT_ACCESS_EXPIRY = process.env.JWT_ACCESS_EXPIRY || '1h';
const JWT_REFRESH_EXPIRY = process.env.JWT_REFRESH_EXPIRY || '7d';
const JWT_ISSUER = process.env.JWT_ISSUER || 'spatial-tag-auth';
const JWT_ALGORITHM = process.env.JWT_ALGORITHM || 'HS256';

// Token payload interface with strict typing
interface TokenPayload extends JwtPayload {
  userId: string;
  email: string;
  statusLevel: StatusLevel;
  type: 'access' | 'refresh';
  fingerprint?: string;
}

/**
 * Generates a secure JWT access token with comprehensive user data
 * @param user - Validated user object
 * @returns Promise resolving to signed JWT access token
 * @throws Error if user object is invalid
 */
export async function generateAccessToken(user: User): Promise<string> {
  if (!user?.id || !user?.email || !user?.statusLevel) {
    throw new Error('Invalid user object provided for token generation');
  }

  const payload: TokenPayload = {
    userId: user.id,
    email: user.email,
    statusLevel: user.statusLevel,
    type: 'access',
    iat: Math.floor(Date.now() / 1000),
    iss: JWT_ISSUER,
    aud: 'spatial-tag-api',
    jti: randomBytes(16).toString('hex')
  };

  try {
    const token = sign(payload, JWT_SECRET, {
      algorithm: JWT_ALGORITHM as 'HS256',
      expiresIn: JWT_ACCESS_EXPIRY
    });

    // Validate generated token format
    await verifyAccessToken(token);
    return token;
  } catch (error) {
    throw new Error(`Failed to generate access token: ${error.message}`);
  }
}

/**
 * Generates a secure JWT refresh token with minimal payload
 * @param user - Validated user object
 * @returns Promise resolving to signed JWT refresh token
 * @throws Error if user ID is invalid
 */
export async function generateRefreshToken(user: User): Promise<string> {
  if (!user?.id) {
    throw new Error('Invalid user ID for refresh token generation');
  }

  const fingerprint = randomBytes(32).toString('hex');
  const payload: TokenPayload = {
    userId: user.id,
    type: 'refresh',
    fingerprint,
    iat: Math.floor(Date.now() / 1000),
    iss: JWT_ISSUER,
    aud: 'spatial-tag-refresh',
    jti: randomBytes(16).toString('hex')
  };

  try {
    const token = sign(payload, JWT_SECRET, {
      algorithm: JWT_ALGORITHM as 'HS256',
      expiresIn: JWT_REFRESH_EXPIRY
    });

    // Validate generated token format
    await verifyRefreshToken(token);
    return token;
  } catch (error) {
    throw new Error(`Failed to generate refresh token: ${error.message}`);
  }
}

/**
 * Verifies and decodes a JWT access token
 * @param token - JWT access token string
 * @returns Promise resolving to decoded token payload
 * @throws UnauthorizedError for invalid tokens
 */
export async function verifyAccessToken(token: string): Promise<TokenPayload> {
  try {
    // Validate token format
    if (!token || typeof token !== 'string') {
      throw new UnauthorizedError('Invalid token format');
    }

    // Verify and decode token
    const decoded = verify(token, JWT_SECRET, {
      algorithms: [JWT_ALGORITHM as 'HS256'],
      issuer: JWT_ISSUER,
      audience: 'spatial-tag-api'
    }) as TokenPayload;

    // Validate token type and payload structure
    if (decoded.type !== 'access' || !decoded.userId || !decoded.email) {
      throw new UnauthorizedError('Invalid token payload structure');
    }

    return decoded;
  } catch (error) {
    if (error.name === 'TokenExpiredError') {
      throw new UnauthorizedError('Token has expired');
    }
    if (error.name === 'JsonWebTokenError') {
      throw new UnauthorizedError('Invalid token signature');
    }
    throw new UnauthorizedError(error.message);
  }
}

/**
 * Verifies and decodes a JWT refresh token
 * @param token - JWT refresh token string
 * @returns Promise resolving to decoded refresh token payload
 * @throws UnauthorizedError for invalid tokens
 */
export async function verifyRefreshToken(token: string): Promise<TokenPayload> {
  try {
    // Validate token format
    if (!token || typeof token !== 'string') {
      throw new UnauthorizedError('Invalid refresh token format');
    }

    // Verify and decode token
    const decoded = verify(token, JWT_SECRET, {
      algorithms: [JWT_ALGORITHM as 'HS256'],
      issuer: JWT_ISSUER,
      audience: 'spatial-tag-refresh'
    }) as TokenPayload;

    // Validate refresh token specific requirements
    if (decoded.type !== 'refresh' || !decoded.userId || !decoded.fingerprint) {
      throw new UnauthorizedError('Invalid refresh token payload structure');
    }

    return decoded;
  } catch (error) {
    if (error.name === 'TokenExpiredError') {
      throw new UnauthorizedError('Refresh token has expired');
    }
    if (error.name === 'JsonWebTokenError') {
      throw new UnauthorizedError('Invalid refresh token signature');
    }
    throw new UnauthorizedError(error.message);
  }
}