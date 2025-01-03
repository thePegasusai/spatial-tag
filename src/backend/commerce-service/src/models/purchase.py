"""
Purchase Model for Commerce Service
Version: 1.0
Description: Secure purchase transaction model with PCI DSS compliance and collaborative shopping support.

External Dependencies:
- sqlalchemy (1.4.x): ORM for database operations
- uuid (python3.11+): Secure UUID generation
- datetime (python3.11+): Timestamp handling
- decimal (python3.11+): Precise financial calculations
- enum (python3.11+): Type-safe status enumeration
"""

import uuid
from datetime import datetime, timezone
from decimal import Decimal
import enum
from typing import Dict, Optional

from sqlalchemy import Column, String, DateTime, Enum, JSON, Numeric
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.ext.declarative import declarative_base

from ..config.settings import STRIPE_CONFIG

Base = declarative_base()

@enum.unique
class PurchaseStatus(enum.Enum):
    """
    Enumeration of possible purchase status values with enhanced state management.
    Ensures type safety and valid state transitions.
    """
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    REFUNDED = "refunded"
    DISPUTED = "disputed"

    def can_transition_to(self, new_status: 'PurchaseStatus') -> bool:
        """Validates if the status transition is allowed based on business rules."""
        VALID_TRANSITIONS = {
            PurchaseStatus.PENDING: {PurchaseStatus.PROCESSING, PurchaseStatus.FAILED},
            PurchaseStatus.PROCESSING: {PurchaseStatus.COMPLETED, PurchaseStatus.FAILED},
            PurchaseStatus.COMPLETED: {PurchaseStatus.REFUNDED, PurchaseStatus.DISPUTED},
            PurchaseStatus.FAILED: {PurchaseStatus.PENDING},
            PurchaseStatus.REFUNDED: {PurchaseStatus.DISPUTED},
            PurchaseStatus.DISPUTED: {PurchaseStatus.COMPLETED, PurchaseStatus.REFUNDED}
        }
        return new_status in VALID_TRANSITIONS.get(self, set())

class Purchase(Base):
    """
    SQLAlchemy model representing a secure purchase transaction with enhanced metadata support.
    Implements PCI DSS compliance and audit trail capabilities.
    """
    __tablename__ = 'purchases'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), nullable=False, index=True)
    amount = Column(Numeric(precision=10, scale=2), nullable=False)
    currency = Column(String(3), nullable=False)
    stripe_payment_intent_id = Column(String(255), nullable=False, unique=True)
    status = Column(Enum(PurchaseStatus), nullable=False, default=PurchaseStatus.PENDING)
    metadata = Column(JSON, nullable=False, default=dict)
    created_at = Column(DateTime(timezone=True), nullable=False)
    updated_at = Column(DateTime(timezone=True), nullable=False)
    status_changed_at = Column(DateTime(timezone=True), nullable=False)
    status_reason = Column(String(255))
    collaborative_data = Column(JSON, nullable=False, default=dict)

    def __init__(
        self,
        user_id: uuid.UUID,
        amount: Decimal,
        currency: str,
        stripe_payment_intent_id: str,
        metadata: Optional[Dict] = None,
        collaborative_data: Optional[Dict] = None
    ):
        """
        Initialize a new purchase record with enhanced security validation.
        
        Args:
            user_id: UUID of the purchasing user
            amount: Transaction amount with precise decimal handling
            currency: Three-letter currency code (must be supported)
            stripe_payment_intent_id: Stripe payment intent identifier
            metadata: Additional transaction metadata
            collaborative_data: Shared shopping experience data
        """
        # Validate input parameters
        if not isinstance(user_id, uuid.UUID):
            raise ValueError("user_id must be a valid UUID")
        
        if not isinstance(amount, Decimal):
            raise ValueError("amount must be a Decimal")
        
        if amount <= Decimal('0'):
            raise ValueError("amount must be greater than 0")
        
        if currency not in STRIPE_CONFIG.ALLOWED_CURRENCIES:
            raise ValueError(f"Currency {currency} is not supported")
        
        if not stripe_payment_intent_id.startswith('pi_'):
            raise ValueError("Invalid Stripe payment intent ID format")

        # Set core attributes
        self.id = uuid.uuid4()
        self.user_id = user_id
        self.amount = amount
        self.currency = currency.upper()
        self.stripe_payment_intent_id = stripe_payment_intent_id
        self.status = PurchaseStatus.PENDING
        
        # Set metadata with sanitization
        self.metadata = self._sanitize_metadata(metadata or {})
        self.collaborative_data = collaborative_data or {}
        
        # Set timestamps
        current_time = datetime.now(timezone.utc)
        self.created_at = current_time
        self.updated_at = current_time
        self.status_changed_at = current_time
        self.status_reason = "Purchase initiated"

    def update_status(self, new_status: PurchaseStatus, reason: str) -> None:
        """
        Updates the purchase status with audit trail.
        
        Args:
            new_status: New status to set
            reason: Reason for the status change
        """
        if not self.status.can_transition_to(new_status):
            raise ValueError(f"Invalid status transition from {self.status} to {new_status}")
        
        if not reason:
            raise ValueError("Status change reason is required")

        current_time = datetime.now(timezone.utc)
        self.status = new_status
        self.status_changed_at = current_time
        self.status_reason = reason
        self.updated_at = current_time

    def to_dict(self) -> Dict:
        """
        Converts purchase record to dictionary format with sensitive data handling.
        
        Returns:
            Dict containing sanitized purchase data
        """
        return {
            'id': str(self.id),
            'user_id': str(self.user_id),
            'amount': str(self.amount),
            'currency': self.currency,
            'status': self.status.value,
            'metadata': self._sanitize_metadata(self.metadata),
            'collaborative_data': self._sanitize_collaborative_data(self.collaborative_data),
            'created_at': self.created_at.isoformat(),
            'updated_at': self.updated_at.isoformat(),
            'status_changed_at': self.status_changed_at.isoformat(),
            'status_reason': self.status_reason
        }

    @staticmethod
    def _sanitize_metadata(metadata: Dict) -> Dict:
        """
        Sanitizes metadata by removing sensitive information.
        
        Args:
            metadata: Raw metadata dictionary
            
        Returns:
            Dict with sanitized metadata
        """
        SENSITIVE_KEYS = {'card', 'cvv', 'password', 'secret'}
        return {
            k: '******' if any(sensitive in k.lower() for sensitive in SENSITIVE_KEYS) else v
            for k, v in metadata.items()
        }

    @staticmethod
    def _sanitize_collaborative_data(data: Dict) -> Dict:
        """
        Sanitizes collaborative shopping data for safe exposure.
        
        Args:
            data: Raw collaborative data dictionary
            
        Returns:
            Dict with sanitized collaborative data
        """
        if not data:
            return {}
            
        return {
            'shared_users': [str(uid) for uid in data.get('shared_users', [])],
            'shared_items': data.get('shared_items', []),
            'total_participants': data.get('total_participants', 0),
            'sharing_enabled': data.get('sharing_enabled', False)
        }