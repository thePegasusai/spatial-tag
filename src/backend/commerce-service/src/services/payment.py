"""
Payment Service Implementation
Version: 1.0
Description: Enhanced payment processing service with PCI DSS compliance,
3D Secure support, and comprehensive security measures.

External Dependencies:
- typing (python3.11+): Type hints
- logging (python3.11+): Structured logging
- decimal (python3.11+): Precise decimal arithmetic
"""

import logging
from typing import Dict, Optional
from decimal import Decimal
from uuid import UUID

from ..models.purchase import Purchase, PurchaseStatus
from ..config.settings import STRIPE_CONFIG, RETRY_CONFIG
from .stripe_client import StripeClient

# Configure logging
logger = logging.getLogger(__name__)

# Constants
PAYMENT_RETRY_ATTEMPTS = 3
SUPPORTED_CURRENCIES = ['USD', 'EUR', 'GBP']

class PaymentService:
    """
    Enhanced payment processing service with comprehensive security,
    retry mechanisms, and audit logging capabilities.
    """

    def __init__(self, db_session, retry_config: Dict = RETRY_CONFIG):
        """
        Initialize payment service with secure configuration.

        Args:
            db_session: Database session for transaction management
            retry_config: Configuration for retry mechanisms
        """
        self._db_session = db_session
        self._stripe_client = StripeClient()
        self._retry_config = retry_config

        logger.info("Payment service initialized with secure configuration")

    async def create_payment(
        self,
        user_id: UUID,
        amount: Decimal,
        currency: str,
        metadata: Optional[Dict] = None
    ) -> Purchase:
        """
        Creates a new payment transaction with enhanced security validation.

        Args:
            user_id: UUID of the purchasing user
            amount: Payment amount
            currency: Three-letter currency code
            metadata: Additional payment metadata

        Returns:
            Purchase: Created purchase record

        Raises:
            ValueError: On validation failure
            PaymentError: On payment processing failure
        """
        try:
            # Validate inputs
            if amount <= Decimal('0'):
                raise ValueError("Payment amount must be greater than 0")

            if currency not in SUPPORTED_CURRENCIES:
                raise ValueError(f"Currency {currency} not supported")

            # Create Stripe payment intent
            payment_intent = await self._stripe_client.create_payment_intent(
                float(amount),
                currency,
                metadata=metadata,
                require_3ds=True
            )

            # Create purchase record
            purchase = Purchase(
                user_id=user_id,
                amount=amount,
                currency=currency,
                stripe_payment_intent_id=payment_intent.id,
                metadata=metadata
            )

            # Persist with transaction
            self._db_session.add(purchase)
            await self._db_session.commit()

            logger.info(
                f"Payment created successfully: {purchase.id}",
                extra={
                    "user_id": str(user_id),
                    "amount": str(amount),
                    "currency": currency
                }
            )

            return purchase

        except Exception as e:
            await self._db_session.rollback()
            logger.error(f"Error creating payment: {str(e)}")
            raise

    async def process_webhook(self, payload: str, signature: str) -> None:
        """
        Processes Stripe webhooks with enhanced security validation.

        Args:
            payload: Raw webhook payload
            signature: Stripe signature header

        Raises:
            WebhookError: On webhook processing failure
        """
        try:
            # Verify webhook signature
            event = self._stripe_client.verify_webhook(payload, signature)

            # Process webhook event
            await self._stripe_client.process_webhook_event(event)

            logger.info(
                f"Webhook processed successfully: {event.type}",
                extra={"event_id": event.id}
            )

        except Exception as e:
            logger.error(f"Error processing webhook: {str(e)}")
            raise

    async def get_payment_status(self, purchase_id: UUID) -> Dict:
        """
        Retrieves payment status with enhanced details.

        Args:
            purchase_id: UUID of the purchase

        Returns:
            Dict: Detailed payment status information

        Raises:
            ValueError: If purchase not found
        """
        try:
            purchase = await self._db_session.query(Purchase).get(purchase_id)
            if not purchase:
                raise ValueError(f"Purchase {purchase_id} not found")

            status_info = purchase.to_dict()
            status_info['payment_details'] = await self._stripe_client.get_payment_intent(
                purchase.stripe_payment_intent_id
            )

            logger.info(
                f"Payment status retrieved: {purchase_id}",
                extra={"status": purchase.status.value}
            )

            return status_info

        except Exception as e:
            logger.error(f"Error retrieving payment status: {str(e)}")
            raise

    async def refund_payment(self, purchase_id: UUID) -> Purchase:
        """
        Processes payment refund with enhanced validation.

        Args:
            purchase_id: UUID of the purchase to refund

        Returns:
            Purchase: Updated purchase record

        Raises:
            ValueError: If purchase not found or not refundable
            RefundError: On refund processing failure
        """
        try:
            purchase = await self._db_session.query(Purchase).get(purchase_id)
            if not purchase:
                raise ValueError(f"Purchase {purchase_id} not found")

            if purchase.status != PurchaseStatus.COMPLETED:
                raise ValueError(f"Purchase {purchase_id} is not eligible for refund")

            # Process refund through Stripe
            refund = await self._stripe_client.refund_payment(
                purchase.stripe_payment_intent_id,
                metadata={"purchase_id": str(purchase_id)}
            )

            # Update purchase status
            purchase.update_status(
                PurchaseStatus.REFUNDED,
                f"Refund processed: {refund.id}"
            )

            await self._db_session.commit()

            logger.info(
                f"Payment refunded successfully: {purchase_id}",
                extra={"refund_id": refund.id}
            )

            return purchase

        except Exception as e:
            await self._db_session.rollback()
            logger.error(f"Error processing refund: {str(e)}")
            raise