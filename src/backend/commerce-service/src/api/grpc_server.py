"""
Enhanced gRPC server implementation for commerce service with comprehensive security,
monitoring, and error handling capabilities.

External Dependencies:
- grpc (1.54.0): gRPC framework
- opentelemetry-api (1.20.0): Distributed tracing
- prometheus_client (0.17.1): Metrics export
"""

import logging
import uuid
from concurrent import futures
from typing import Dict, Optional
from decimal import Decimal

import grpc
from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode
from prometheus_client import Counter, Histogram

from ..services.wishlist import WishlistService
from ..services.payment import PaymentService
import commerce_pb2
import commerce_pb2_grpc

# Configure logging
logger = logging.getLogger(__name__)

# Initialize OpenTelemetry tracer
tracer = trace.get_tracer(__name__)

# Define Prometheus metrics
REQUEST_COUNTER = Counter(
    'commerce_requests_total',
    'Total number of commerce service requests',
    ['method', 'status']
)

LATENCY_HISTOGRAM = Histogram(
    'commerce_request_latency_seconds',
    'Request latency in seconds',
    ['method']
)

class CommerceServicer(commerce_pb2_grpc.CommerceServiceServicer):
    """
    Enhanced gRPC service implementation for commerce operations with comprehensive
    security, monitoring, and error handling.
    """

    def __init__(self, db_session):
        """
        Initialize commerce servicer with required services and monitoring.

        Args:
            db_session: Database session for transaction management
        """
        self._wishlist_service = WishlistService(db_session)
        self._payment_service = PaymentService(db_session)
        self._setup_monitoring()

    def _setup_monitoring(self):
        """Configure monitoring and tracing infrastructure."""
        # Additional monitoring setup if needed
        pass

    def _validate_request(self, request) -> bool:
        """
        Validate incoming request data.

        Args:
            request: gRPC request object

        Returns:
            bool: Validation result
        """
        if not request:
            return False
        return True

    @trace.span
    async def CreateWishlist(
        self,
        request: commerce_pb2.CreateWishlistRequest,
        context: grpc.ServicerContext
    ) -> commerce_pb2.Wishlist:
        """
        Creates a new wishlist with enhanced validation and monitoring.

        Args:
            request: Wishlist creation request
            context: gRPC service context

        Returns:
            commerce_pb2.Wishlist: Created wishlist response
        """
        with LATENCY_HISTOGRAM.labels(method='CreateWishlist').time():
            try:
                # Validate request
                if not self._validate_request(request):
                    context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
                    context.set_details("Invalid request parameters")
                    REQUEST_COUNTER.labels(
                        method='CreateWishlist',
                        status='invalid_argument'
                    ).inc()
                    return commerce_pb2.Wishlist()

                # Create wishlist
                wishlist = await self._wishlist_service.create_wishlist(
                    user_id=uuid.UUID(request.user_id),
                    name=request.name,
                    visibility=request.visibility
                )

                # Convert to response
                response = commerce_pb2.Wishlist(
                    id=str(wishlist.id),
                    user_id=str(wishlist.user_id),
                    name=wishlist.name,
                    visibility=wishlist.visibility.value,
                    created_at=wishlist.created_at.isoformat(),
                    updated_at=wishlist.updated_at.isoformat()
                )

                REQUEST_COUNTER.labels(
                    method='CreateWishlist',
                    status='success'
                ).inc()
                return response

            except ValueError as e:
                context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
                context.set_details(str(e))
                REQUEST_COUNTER.labels(
                    method='CreateWishlist',
                    status='invalid_argument'
                ).inc()
                return commerce_pb2.Wishlist()

            except Exception as e:
                logger.error(f"Error creating wishlist: {str(e)}")
                context.set_code(grpc.StatusCode.INTERNAL)
                context.set_details("Internal server error")
                REQUEST_COUNTER.labels(
                    method='CreateWishlist',
                    status='error'
                ).inc()
                return commerce_pb2.Wishlist()

    @trace.span
    async def GetWishlist(
        self,
        request: commerce_pb2.GetWishlistRequest,
        context: grpc.ServicerContext
    ) -> commerce_pb2.Wishlist:
        """
        Retrieves a wishlist by ID with enhanced error handling.

        Args:
            request: Wishlist retrieval request
            context: gRPC service context

        Returns:
            commerce_pb2.Wishlist: Retrieved wishlist response
        """
        with LATENCY_HISTOGRAM.labels(method='GetWishlist').time():
            try:
                wishlist = await self._wishlist_service.get_wishlist(
                    wishlist_id=uuid.UUID(request.wishlist_id)
                )

                if not wishlist:
                    context.set_code(grpc.StatusCode.NOT_FOUND)
                    context.set_details("Wishlist not found")
                    REQUEST_COUNTER.labels(
                        method='GetWishlist',
                        status='not_found'
                    ).inc()
                    return commerce_pb2.Wishlist()

                response = commerce_pb2.Wishlist(
                    id=str(wishlist.id),
                    user_id=str(wishlist.user_id),
                    name=wishlist.name,
                    visibility=wishlist.visibility.value,
                    created_at=wishlist.created_at.isoformat(),
                    updated_at=wishlist.updated_at.isoformat()
                )

                REQUEST_COUNTER.labels(
                    method='GetWishlist',
                    status='success'
                ).inc()
                return response

            except ValueError as e:
                context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
                context.set_details(str(e))
                REQUEST_COUNTER.labels(
                    method='GetWishlist',
                    status='invalid_argument'
                ).inc()
                return commerce_pb2.Wishlist()

            except Exception as e:
                logger.error(f"Error retrieving wishlist: {str(e)}")
                context.set_code(grpc.StatusCode.INTERNAL)
                context.set_details("Internal server error")
                REQUEST_COUNTER.labels(
                    method='GetWishlist',
                    status='error'
                ).inc()
                return commerce_pb2.Wishlist()

    @trace.span
    async def CreatePaymentIntent(
        self,
        request: commerce_pb2.CreatePaymentIntentRequest,
        context: grpc.ServicerContext
    ) -> commerce_pb2.PaymentIntent:
        """
        Creates a secure payment intent with comprehensive validation.

        Args:
            request: Payment intent creation request
            context: gRPC service context

        Returns:
            commerce_pb2.PaymentIntent: Created payment intent response
        """
        with LATENCY_HISTOGRAM.labels(method='CreatePaymentIntent').time():
            try:
                # Validate request
                if not self._validate_request(request):
                    context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
                    context.set_details("Invalid request parameters")
                    REQUEST_COUNTER.labels(
                        method='CreatePaymentIntent',
                        status='invalid_argument'
                    ).inc()
                    return commerce_pb2.PaymentIntent()

                # Create payment
                purchase = await self._payment_service.create_payment(
                    user_id=uuid.UUID(request.user_id),
                    amount=Decimal(str(request.amount)),
                    currency=request.currency,
                    metadata=request.metadata
                )

                response = commerce_pb2.PaymentIntent(
                    id=str(purchase.id),
                    user_id=str(purchase.user_id),
                    amount=str(purchase.amount),
                    currency=purchase.currency,
                    status=purchase.status.value,
                    created_at=purchase.created_at.isoformat()
                )

                REQUEST_COUNTER.labels(
                    method='CreatePaymentIntent',
                    status='success'
                ).inc()
                return response

            except ValueError as e:
                context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
                context.set_details(str(e))
                REQUEST_COUNTER.labels(
                    method='CreatePaymentIntent',
                    status='invalid_argument'
                ).inc()
                return commerce_pb2.PaymentIntent()

            except Exception as e:
                logger.error(f"Error creating payment intent: {str(e)}")
                context.set_code(grpc.StatusCode.INTERNAL)
                context.set_details("Internal server error")
                REQUEST_COUNTER.labels(
                    method='CreatePaymentIntent',
                    status='error'
                ).inc()
                return commerce_pb2.PaymentIntent()

    @trace.span
    async def GetPaymentStatus(
        self,
        request: commerce_pb2.GetPaymentStatusRequest,
        context: grpc.ServicerContext
    ) -> commerce_pb2.PaymentStatus:
        """
        Retrieves payment status with enhanced error handling.

        Args:
            request: Payment status request
            context: gRPC service context

        Returns:
            commerce_pb2.PaymentStatus: Payment status response
        """
        with LATENCY_HISTOGRAM.labels(method='GetPaymentStatus').time():
            try:
                status_info = await self._payment_service.get_payment_status(
                    purchase_id=uuid.UUID(request.payment_id)
                )

                response = commerce_pb2.PaymentStatus(
                    payment_id=str(status_info['id']),
                    status=status_info['status'],
                    amount=str(status_info['amount']),
                    currency=status_info['currency'],
                    updated_at=status_info['updated_at']
                )

                REQUEST_COUNTER.labels(
                    method='GetPaymentStatus',
                    status='success'
                ).inc()
                return response

            except ValueError as e:
                context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
                context.set_details(str(e))
                REQUEST_COUNTER.labels(
                    method='GetPaymentStatus',
                    status='invalid_argument'
                ).inc()
                return commerce_pb2.PaymentStatus()

            except Exception as e:
                logger.error(f"Error retrieving payment status: {str(e)}")
                context.set_code(grpc.StatusCode.INTERNAL)
                context.set_details("Internal server error")
                REQUEST_COUNTER.labels(
                    method='GetPaymentStatus',
                    status='error'
                ).inc()
                return commerce_pb2.PaymentStatus()