// @ts-version 5.0

import express, { Request, Response } from 'express'; // v4.18.2
import { body, param, validationResult } from 'express-validator'; // v7.0.1
import rateLimit from 'express-rate-limit'; // v7.1.0
import Stripe from 'stripe'; // v14.0.0

import { authenticate } from '../middleware/auth';
import { GrpcClient } from '../services/grpc-client';
import { APIError, ErrorCodes, WishlistResponse } from '../types';

// Initialize router and dependencies
const router = express.Router();
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
  apiVersion: '2023-10-16',
  typescript: true,
});

// Rate limiting configurations
const wishlistRateLimit = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 50,
  message: 'Too many wishlist operations, please try again later'
});

const paymentRateLimit = rateLimit({
  windowMs: 60 * 1000,
  max: 20,
  message: 'Too many payment attempts, please try again later'
});

// Validation middleware
const validateWishlist = [
  body('visibility').isIn(['VISIBILITY_PRIVATE', 'VISIBILITY_FRIENDS', 'VISIBILITY_PUBLIC']),
  body('collaboration_settings').isObject(),
  body('collaboration_settings.allow_item_addition').isBoolean(),
  body('collaboration_settings.allow_item_removal').isBoolean(),
  body('collaboration_settings.allow_price_updates').isBoolean(),
  body('collaboration_settings.notify_on_changes').isBoolean()
];

const validatePayment = [
  body('amount').isFloat({ min: 0.01 }),
  body('currency').isString().isLength({ min: 3, max: 3 }),
  body('payment_method_id').isString(),
  body('description').optional().isString(),
  body('metadata').optional().isObject()
];

// Create new wishlist
router.post('/wishlists', 
  authenticate,
  wishlistRateLimit,
  validateWishlist,
  async (req: Request, res: Response) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        throw new APIError(ErrorCodes.VALIDATION_ERROR, 'Invalid wishlist data', errors.array());
      }

      const grpcClient = await GrpcClient.getCommerceService();
      const response = await grpcClient.CreateWishlist({
        user_id: req.user!.id,
        visibility: req.body.visibility,
        collaboration_settings: req.body.collaboration_settings
      });

      res.status(201).json({
        success: true,
        data: response,
        metadata: {
          timestamp: new Date().toISOString()
        }
      });
    } catch (error) {
      throw new APIError(
        ErrorCodes.COMMERCE_ERROR,
        'Failed to create wishlist',
        { error }
      );
    }
});

// Get wishlist with collaborators
router.get('/wishlists/:id',
  authenticate,
  param('id').isUUID(),
  async (req: Request, res: Response) => {
    try {
      const grpcClient = await GrpcClient.getCommerceService();
      const wishlist = await grpcClient.GetWishlist({
        wishlist_id: req.params.id,
        user_id: req.user!.id
      });

      // Enhance wishlist with status-based features
      const statusService = await GrpcClient.getStatusService();
      const userStatus = await statusService.GetUserStatus({ user_id: req.user!.id });
      
      const enhancedWishlist: WishlistResponse = {
        ...wishlist,
        collaboration_settings: {
          ...wishlist.collaboration_settings,
          // Elite users get additional collaboration features
          allowItemAddition: userStatus.level >= 2 ? true : wishlist.collaboration_settings.allow_item_addition,
          allowPriceUpdates: userStatus.level >= 2 ? true : wishlist.collaboration_settings.allow_price_updates
        }
      };

      res.json({
        success: true,
        data: enhancedWishlist,
        metadata: {
          timestamp: new Date().toISOString()
        }
      });
    } catch (error) {
      throw new APIError(
        ErrorCodes.COMMERCE_ERROR,
        'Failed to retrieve wishlist',
        { error }
      );
    }
});

// Update wishlist
router.put('/wishlists/:id',
  authenticate,
  wishlistRateLimit,
  validateWishlist,
  param('id').isUUID(),
  async (req: Request, res: Response) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        throw new APIError(ErrorCodes.VALIDATION_ERROR, 'Invalid wishlist data', errors.array());
      }

      const grpcClient = await GrpcClient.getCommerceService();
      const response = await grpcClient.UpdateWishlist({
        wishlist_id: req.params.id,
        visibility: req.body.visibility,
        collaboration_settings: req.body.collaboration_settings
      });

      res.json({
        success: true,
        data: response,
        metadata: {
          timestamp: new Date().toISOString()
        }
      });
    } catch (error) {
      throw new APIError(
        ErrorCodes.COMMERCE_ERROR,
        'Failed to update wishlist',
        { error }
      );
    }
});

// Share wishlist
router.post('/wishlists/:id/share',
  authenticate,
  wishlistRateLimit,
  param('id').isUUID(),
  body('user_ids').isArray(),
  body('visibility').isIn(['VISIBILITY_FRIENDS', 'VISIBILITY_PUBLIC']),
  async (req: Request, res: Response) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        throw new APIError(ErrorCodes.VALIDATION_ERROR, 'Invalid share data', errors.array());
      }

      const grpcClient = await GrpcClient.getCommerceService();
      const response = await grpcClient.ShareWishlist({
        wishlist_id: req.params.id,
        user_ids: req.body.user_ids,
        visibility: req.body.visibility
      });

      res.json({
        success: true,
        data: response,
        metadata: {
          timestamp: new Date().toISOString()
        }
      });
    } catch (error) {
      throw new APIError(
        ErrorCodes.COMMERCE_ERROR,
        'Failed to share wishlist',
        { error }
      );
    }
});

// Process payment
router.post('/payments',
  authenticate,
  paymentRateLimit,
  validatePayment,
  async (req: Request, res: Response) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        throw new APIError(ErrorCodes.VALIDATION_ERROR, 'Invalid payment data', errors.array());
      }

      // Create Stripe payment intent
      const paymentIntent = await stripe.paymentIntents.create({
        amount: Math.round(req.body.amount * 100), // Convert to cents
        currency: req.body.currency,
        payment_method: req.body.payment_method_id,
        confirm: true,
        metadata: {
          user_id: req.user!.id,
          ...req.body.metadata
        }
      });

      // Record payment in commerce service
      const grpcClient = await GrpcClient.getCommerceService();
      const commercePayment = await grpcClient.CreatePaymentIntent({
        user_id: req.user!.id,
        stripe_payment_intent_id: paymentIntent.id,
        amount: req.body.amount,
        currency: req.body.currency,
        description: req.body.description,
        metadata: req.body.metadata
      });

      res.json({
        success: true,
        data: {
          payment_intent: paymentIntent.client_secret,
          commerce_payment: commercePayment
        },
        metadata: {
          timestamp: new Date().toISOString()
        }
      });
    } catch (error) {
      throw new APIError(
        ErrorCodes.COMMERCE_ERROR,
        'Payment processing failed',
        { error }
      );
    }
});

// Get payment status
router.get('/payments/:id',
  authenticate,
  param('id').isString(),
  async (req: Request, res: Response) => {
    try {
      const grpcClient = await GrpcClient.getCommerceService();
      const payment = await grpcClient.GetPaymentStatus({
        payment_intent_id: req.params.id
      });

      res.json({
        success: true,
        data: payment,
        metadata: {
          timestamp: new Date().toISOString()
        }
      });
    } catch (error) {
      throw new APIError(
        ErrorCodes.COMMERCE_ERROR,
        'Failed to retrieve payment status',
        { error }
      );
    }
});

export default router;