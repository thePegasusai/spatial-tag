// @ts-check
import { IsEmail, MinLength, IsString } from 'class-validator'; // v0.14.x
import { BadRequest, Unauthorized, TooManyRequests } from '@hapi/boom'; // v10.0.1
import { User, UserDocument, StatusLevel } from '../types';
import { UserModel } from '../models/user';
import {
  generateAccessToken,
  generateRefreshToken,
  verifyAccessToken,
  verifyRefreshToken
} from '../config/jwt';

// Constants for authentication rules and rate limiting
const PASSWORD_MIN_LENGTH = 8;
const EMAIL_REGEX = /^[^@]+@[^@]+\.[^@]+$/;
const MAX_LOGIN_ATTEMPTS = 5;
const LOGIN_LOCKOUT_DURATION = 15 * 60 * 1000; // 15 minutes
const TOKEN_EXPIRY = {
  access: 3600, // 1 hour
  refresh: 604800 // 7 days
};

// Rate limiting tracking with Map
const loginAttempts = new Map<string, { count: number; timestamp: number }>();

// Response type definitions
interface AuthResponse {
  accessToken: string;
  refreshToken: string;
  user: Partial<User>;
  expiresIn: number;
}

interface TokenResponse {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
}

class LoginDto {
  @IsEmail()
  email!: string;

  @IsString()
  @MinLength(PASSWORD_MIN_LENGTH)
  password!: string;
}

/**
 * Authenticates a user with email and password
 * @param email - User's email address
 * @param password - User's password
 * @returns Promise resolving to authentication response
 * @throws BadRequest for invalid credentials
 * @throws TooManyRequests for rate limit violations
 */
export async function login(email: string, password: string): Promise<AuthResponse> {
  // Validate input format
  if (!email || !EMAIL_REGEX.test(email)) {
    throw new BadRequest('Invalid email format');
  }

  if (!password || password.length < PASSWORD_MIN_LENGTH) {
    throw new BadRequest('Invalid password format');
  }

  // Check rate limiting
  const attempts = loginAttempts.get(email);
  if (attempts) {
    if (attempts.count >= MAX_LOGIN_ATTEMPTS) {
      const timeElapsed = Date.now() - attempts.timestamp;
      if (timeElapsed < LOGIN_LOCKOUT_DURATION) {
        throw new TooManyRequests('Too many login attempts. Please try again later.');
      }
      loginAttempts.delete(email);
    }
  }

  try {
    // Find user and verify password
    const user = await UserModel.findByEmail(email.toLowerCase().trim());
    if (!user) {
      throw new Unauthorized('Invalid credentials');
    }

    const isValidPassword = await user.comparePassword(password);
    if (!isValidPassword) {
      // Track failed attempt
      const currentAttempts = loginAttempts.get(email) || { count: 0, timestamp: Date.now() };
      loginAttempts.set(email, {
        count: currentAttempts.count + 1,
        timestamp: Date.now()
      });
      throw new Unauthorized('Invalid credentials');
    }

    // Generate tokens
    const [accessToken, refreshToken] = await Promise.all([
      generateAccessToken(user),
      generateRefreshToken(user)
    ]);

    // Clear login attempts on successful login
    loginAttempts.delete(email);

    return {
      accessToken,
      refreshToken,
      user: user.toJSON(),
      expiresIn: TOKEN_EXPIRY.access
    };
  } catch (error) {
    if (error.isBoom) throw error;
    throw new BadRequest('Authentication failed');
  }
}

/**
 * Registers a new user account
 * @param email - User's email address
 * @param password - User's password
 * @returns Promise resolving to authentication response
 * @throws BadRequest for invalid input or existing email
 */
export async function register(email: string, password: string): Promise<AuthResponse> {
  // Validate input format
  if (!email || !EMAIL_REGEX.test(email)) {
    throw new BadRequest('Invalid email format');
  }

  if (!password || password.length < PASSWORD_MIN_LENGTH) {
    throw new BadRequest('Password must be at least 8 characters');
  }

  try {
    // Check for existing user
    const existingUser = await UserModel.findByEmail(email.toLowerCase().trim());
    if (existingUser) {
      throw new BadRequest('Email already registered');
    }

    // Create new user
    const user = await UserModel.createUser(email, password);

    // Generate tokens
    const [accessToken, refreshToken] = await Promise.all([
      generateAccessToken(user),
      generateRefreshToken(user)
    ]);

    return {
      accessToken,
      refreshToken,
      user: user.toJSON(),
      expiresIn: TOKEN_EXPIRY.access
    };
  } catch (error) {
    if (error.isBoom) throw error;
    throw new BadRequest('Registration failed');
  }
}

/**
 * Refreshes access token using refresh token
 * @param refreshToken - Valid refresh token
 * @returns Promise resolving to new token pair
 * @throws Unauthorized for invalid refresh token
 */
export async function refreshToken(refreshToken: string): Promise<TokenResponse> {
  if (!refreshToken) {
    throw new Unauthorized('Refresh token required');
  }

  try {
    // Verify refresh token
    const decoded = await verifyRefreshToken(refreshToken);
    const user = await UserModel.findById(decoded.userId);

    if (!user) {
      throw new Unauthorized('User not found');
    }

    // Generate new token pair
    const [newAccessToken, newRefreshToken] = await Promise.all([
      generateAccessToken(user),
      generateRefreshToken(user)
    ]);

    return {
      accessToken: newAccessToken,
      refreshToken: newRefreshToken,
      expiresIn: TOKEN_EXPIRY.access
    };
  } catch (error) {
    throw new Unauthorized('Invalid refresh token');
  }
}

/**
 * Validates current user session
 * @param accessToken - Valid access token
 * @returns Promise resolving to current user data
 * @throws Unauthorized for invalid session
 */
export async function validateSession(accessToken: string): Promise<User> {
  if (!accessToken) {
    throw new Unauthorized('Access token required');
  }

  try {
    // Verify access token
    const decoded = await verifyAccessToken(accessToken);
    const user = await UserModel.findById(decoded.userId);

    if (!user) {
      throw new Unauthorized('User not found');
    }

    return user.toJSON();
  } catch (error) {
    throw new Unauthorized('Invalid session');
  }
}