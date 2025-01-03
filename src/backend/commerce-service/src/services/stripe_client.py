"""
Stripe Payment Processing Client
Version: 1.0
Description: Enhanced Stripe client implementation for secure payment processing with
PCI DSS compliance, 3D Secure support, and comprehensive error handling.

External Dependencies:
- stripe (5.4.0): Stripe SDK for payment processing
- tenacity (8.2.2): Retry handling for API operations
- typing (python3.11+): Type hints
- logging (python3.11+): Logging functionality
"""

import logging
import time
from typing import Dict, Optional, Any
from tenacity import retry, stop_after_attempt, wait_exponential

import stripe

from ..config.settings import STRIPE_CONFIG
from ..models.purchase import Purchase, PurchaseStatus

# Configure logging
logger = logging.getLogger(__name__)

# Constants
PAYMENT_TIMEOUT = 30  # seconds
MAX_RETRIES = 3

class StripeClient:
    """
    Enhanced Stripe client for secure payment processing with comprehensive
    error handling, monitoring, and PCI DSS compliance.
    """
    
    def __init__(self, timeout: int = PAYMENT_TIMEOUT):
        """
        Initialize Stripe client with secure configuration.
        
        Args:
            timeout: Request timeout in seconds
        """
        # Initialize Stripe configuration
        self._api_key = STRIPE_CONFIG.API_KEY
        self._webhook_secret = STRIPE_CONFIG.WEBHOOK_SECRET
        self._api_version = "2023-10-16"  # Lock API version for stability
        self._timeout = timeout
        
        # Configure Stripe client
        stripe.api_key = self._api_key
        stripe.api_version = self._api_version
        stripe.max_network_retries = 2
        stripe.verify_ssl_certs = True
        
        logger.info("Stripe client initialized with secure configuration")

    @retry(
        stop=stop_after_attempt(MAX_RETRIES),
        wait=wait_exponential(multiplier=1, min=4, max=10)
    )
    def create_payment_intent(
        self,
        amount: float,
        currency: str,
        metadata: Optional[Dict[str, Any]] = None,
        require_3ds: bool = True
    ) -> stripe.PaymentIntent:
        """
        Creates a secure payment intent with 3D Secure support.
        
        Args:
            amount: Payment amount
            currency: Three-letter currency code
            metadata: Additional payment metadata
            require_3ds: Enforce 3D Secure authentication
            
        Returns:
            stripe.PaymentIntent: Created payment intent
            
        Raises:
            stripe.error.StripeError: On payment processing failure
        """
        try:
            # Validate currency
            if currency not in STRIPE_CONFIG.ALLOWED_CURRENCIES:
                raise ValueError(f"Currency {currency} not supported")

            # Prepare payment intent parameters
            payment_intent_params = {
                "amount": int(amount * 100),  # Convert to cents
                "currency": currency.lower(),
                "metadata": metadata or {},
                "payment_method_types": ["card"],
                "payment_method_options": {
                    "card": {
                        "request_three_d_secure": "automatic" if require_3ds else "any"
                    }
                },
                "automatic_payment_methods": {
                    "enabled": True,
                    "allow_redirects": "always"
                }
            }

            # Create payment intent with idempotency key
            idempotency_key = f"pi_{time.time()}_{amount}_{currency}"
            payment_intent = stripe.PaymentIntent.create(
                **payment_intent_params,
                idempotency_key=idempotency_key
            )

            logger.info(
                f"Payment intent created successfully: {payment_intent.id}",
                extra={"amount": amount, "currency": currency}
            )
            
            return payment_intent

        except stripe.error.StripeError as e:
            logger.error(
                f"Stripe error creating payment intent: {str(e)}",
                extra={"error_code": e.code, "error_type": type(e).__name__}
            )
            raise
        except Exception as e:
            logger.error(f"Unexpected error creating payment intent: {str(e)}")
            raise

    def verify_webhook(self, payload: str, signature: str) -> stripe.Event:
        """
        Securely verifies Stripe webhook signatures.
        
        Args:
            payload: Raw webhook payload
            signature: Stripe signature header
            
        Returns:
            stripe.Event: Verified webhook event
            
        Raises:
            stripe.error.SignatureVerificationError: On signature verification failure
        """
        try:
            # Verify webhook signature
            event = stripe.Webhook.construct_event(
                payload,
                signature,
                self._webhook_secret,
                tolerance=300  # 5 minute tolerance
            )

            logger.info(
                f"Webhook verified successfully: {event.type}",
                extra={"event_id": event.id}
            )
            
            return event

        except stripe.error.SignatureVerificationError as e:
            logger.error(f"Webhook signature verification failed: {str(e)}")
            raise
        except Exception as e:
            logger.error(f"Unexpected error verifying webhook: {str(e)}")
            raise

    def process_webhook_event(self, event: stripe.Event) -> None:
        """
        Processes Stripe webhook events with comprehensive error handling.
        
        Args:
            event: Verified Stripe event
        """
        try:
            # Handle different event types
            if event.type.startswith('payment_intent.'):
                self._handle_payment_intent_event(event)
            elif event.type.startswith('charge.'):
                self._handle_charge_event(event)
            elif event.type.startswith('refund.'):
                self._handle_refund_event(event)
            else:
                logger.warning(f"Unhandled webhook event type: {event.type}")

        except Exception as e:
            logger.error(
                f"Error processing webhook event: {str(e)}",
                extra={"event_type": event.type, "event_id": event.id}
            )
            raise

    @retry(
        stop=stop_after_attempt(MAX_RETRIES),
        wait=wait_exponential(multiplier=1, min=4, max=10)
    )
    def refund_payment(
        self,
        payment_intent_id: str,
        amount: Optional[float] = None,
        metadata: Optional[Dict[str, Any]] = None
    ) -> stripe.Refund:
        """
        Processes secure payment refunds.
        
        Args:
            payment_intent_id: Stripe payment intent ID
            amount: Refund amount (None for full refund)
            metadata: Additional refund metadata
            
        Returns:
            stripe.Refund: Created refund object
            
        Raises:
            stripe.error.StripeError: On refund processing failure
        """
        try:
            # Prepare refund parameters
            refund_params = {
                "payment_intent": payment_intent_id,
                "metadata": metadata or {}
            }
            
            if amount is not None:
                refund_params["amount"] = int(amount * 100)  # Convert to cents

            # Create refund with idempotency key
            idempotency_key = f"rf_{time.time()}_{payment_intent_id}"
            refund = stripe.Refund.create(
                **refund_params,
                idempotency_key=idempotency_key
            )

            logger.info(
                f"Refund processed successfully: {refund.id}",
                extra={"payment_intent_id": payment_intent_id}
            )
            
            return refund

        except stripe.error.StripeError as e:
            logger.error(
                f"Stripe error processing refund: {str(e)}",
                extra={"error_code": e.code, "payment_intent_id": payment_intent_id}
            )
            raise
        except Exception as e:
            logger.error(f"Unexpected error processing refund: {str(e)}")
            raise

    def _handle_payment_intent_event(self, event: stripe.Event) -> None:
        """
        Handles payment intent related webhook events.
        
        Args:
            event: Stripe event object
        """
        payment_intent = event.data.object
        
        status_mapping = {
            'succeeded': PurchaseStatus.COMPLETED,
            'canceled': PurchaseStatus.FAILED,
            'processing': PurchaseStatus.PROCESSING,
            'requires_payment_method': PurchaseStatus.PENDING
        }
        
        if payment_intent.status in status_mapping:
            Purchase.update_status(
                payment_intent.id,
                status_mapping[payment_intent.status],
                f"Payment {payment_intent.status}"
            )

    def _handle_charge_event(self, event: stripe.Event) -> None:
        """
        Handles charge related webhook events.
        
        Args:
            event: Stripe event object
        """
        charge = event.data.object
        
        if event.type == 'charge.dispute.created':
            Purchase.update_status(
                charge.payment_intent,
                PurchaseStatus.DISPUTED,
                "Payment disputed"
            )

    def _handle_refund_event(self, event: stripe.Event) -> None:
        """
        Handles refund related webhook events.
        
        Args:
            event: Stripe event object
        """
        refund = event.data.object
        
        if event.type == 'refund.succeeded':
            Purchase.update_status(
                refund.payment_intent,
                PurchaseStatus.REFUNDED,
                "Payment refunded"
            )