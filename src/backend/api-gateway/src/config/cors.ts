import cors from 'cors'; // cors@2.8.x
import { RequestHandler } from 'express';

// Environment configuration
const NODE_ENV = process.env.NODE_ENV || 'development';

// Environment-specific allowed origins
const ALLOWED_ORIGINS = {
    development: ['http://localhost:3000', 'http://localhost:8080'],
    staging: ['https://staging.spatialtag.com'],
    production: ['https://spatialtag.com', 'https://*.spatialtag.com']
} as const;

// Allowed HTTP methods
const ALLOWED_METHODS = ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'] as const;

// Allowed headers
const ALLOWED_HEADERS = [
    'Content-Type',
    'Authorization',
    'X-Requested-With',
    'Accept',
    'Origin',
    'X-API-Key'
] as const;

// Security headers
const SECURITY_HEADERS = [
    'Strict-Transport-Security',
    'X-Content-Type-Options',
    'X-Frame-Options',
    'X-XSS-Protection'
] as const;

// CORS max age for preflight requests (24 hours)
const MAX_AGE = 86400;

/**
 * Validates incoming origin against environment-specific allowed origins
 * @param origin - The origin of the incoming request
 * @returns boolean indicating if the origin is allowed
 */
const validateOrigin = (origin: string | undefined): boolean => {
    if (!origin) return false;

    const allowedOrigins = ALLOWED_ORIGINS[NODE_ENV as keyof typeof ALLOWED_ORIGINS];
    
    // Direct match check
    if (allowedOrigins.includes(origin)) {
        return true;
    }

    // Production wildcard subdomain check
    if (NODE_ENV === 'production') {
        const wildcardPattern = allowedOrigins.find(pattern => pattern.includes('*'));
        if (wildcardPattern) {
            const regex = new RegExp(
                '^' + wildcardPattern.replace('*', '[a-zA-Z0-9-]+') + '$'
            );
            return regex.test(origin);
        }
    }

    return false;
};

/**
 * Creates and configures the CORS middleware with comprehensive security settings
 * @returns Configured CORS middleware function
 */
const corsMiddleware = (): RequestHandler => {
    return cors({
        // Origin validation
        origin: (origin, callback) => {
            if (!origin || validateOrigin(origin)) {
                callback(null, true);
            } else {
                callback(new Error('Origin not allowed by CORS'));
            }
        },

        // Method restrictions
        methods: ALLOWED_METHODS,

        // Allowed headers
        allowedHeaders: ALLOWED_HEADERS,
        exposedHeaders: SECURITY_HEADERS,

        // Credentials support
        credentials: true,

        // Preflight configuration
        preflightContinue: false,
        optionsSuccessStatus: 204,
        maxAge: MAX_AGE,

        // Security enhancements
        private: true // Prevents middleware from adding CORS headers if origin is not allowed
    });
};

export default corsMiddleware;