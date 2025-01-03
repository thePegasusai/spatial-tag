"""
SQLAlchemy model definitions for wishlist functionality in the commerce service.
Implements data structures and business logic for user wishlists and shared shopping experiences.

External Dependencies:
sqlalchemy==2.0.0
"""

from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal
from enum import Enum, unique
from typing import Dict, List, Optional, Any
import uuid
from sqlalchemy import Column, String, Boolean, DateTime, Enum as SQLEnum, ForeignKey, Integer
from sqlalchemy.dialects.postgresql import UUID, ARRAY
from sqlalchemy.types import TypeDecorator
from sqlalchemy.orm import relationship
from sqlalchemy.ext.mutable import MutableList

@unique
class WishlistVisibility(str, Enum):
    """Enumeration defining visibility levels for wishlists with enhanced access control."""
    PRIVATE = "private"
    SHARED = "shared"
    PUBLIC = "public"

class DecimalType(TypeDecorator):
    """Custom SQLAlchemy type for handling Decimal values with precision."""
    impl = String
    cache_ok = True

    def process_bind_param(self, value, dialect):
        if value is not None:
            return str(value)
        return None

    def process_result_value(self, value, dialect):
        if value is not None:
            return Decimal(value)
        return None

@dataclass
class WishlistItem:
    """SQLAlchemy model representing an item in a wishlist with enhanced validation."""
    __tablename__ = 'wishlist_items'

    id: UUID = Column(UUID(as_uuid=True), primary_key=True)
    wishlist_id: UUID = Column(UUID(as_uuid=True), ForeignKey('wishlists.id'), nullable=False)
    product_id: str = Column(String(50), nullable=False)
    name: str = Column(String(200), nullable=False)
    price: Decimal = Column(DecimalType, nullable=False)
    currency: str = Column(String(3), nullable=False)
    image_url: Optional[str] = Column(String(500))
    added_at: datetime = Column(DateTime(timezone=True), nullable=False)
    updated_at: Optional[datetime] = Column(DateTime(timezone=True))
    is_active: bool = Column(Boolean, default=True, nullable=False)

    def __init__(self, product_id: str, name: str, price: Decimal, 
                 currency: str, image_url: Optional[str] = None) -> None:
        """Initialize a new wishlist item with validation."""
        if not product_id or len(product_id) > 50:
            raise ValueError("Invalid product_id format")
        if price <= Decimal('0'):
            raise ValueError("Price must be positive")
        if not currency or len(currency) != 3:
            raise ValueError("Invalid currency code format")
        if image_url and len(image_url) > 500:
            raise ValueError("Invalid image_url format")

        self.id = uuid.uuid4()
        self.product_id = product_id
        self.name = name
        self.price = price
        self.currency = currency.upper()
        self.image_url = image_url
        self.added_at = datetime.now(timezone.utc)
        self.is_active = True

    def to_dict(self, fields: Optional[List[str]] = None) -> Dict[str, Any]:
        """Convert wishlist item to dictionary format with optional field filtering."""
        data = {
            'id': str(self.id),
            'wishlist_id': str(self.wishlist_id),
            'product_id': self.product_id,
            'name': self.name,
            'price': str(self.price),
            'currency': self.currency,
            'image_url': self.image_url,
            'added_at': self.added_at.isoformat(),
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
            'is_active': self.is_active
        }
        if fields:
            return {k: v for k, v in data.items() if k in fields}
        return data

@dataclass
class Wishlist:
    """SQLAlchemy model representing a user's wishlist with enhanced sharing capabilities."""
    __tablename__ = 'wishlists'

    id: UUID = Column(UUID(as_uuid=True), primary_key=True)
    user_id: UUID = Column(UUID(as_uuid=True), nullable=False)
    name: str = Column(String(100), nullable=False)
    items: List[WishlistItem] = relationship("WishlistItem", backref="wishlist", lazy="joined")
    visibility: WishlistVisibility = Column(SQLEnum(WishlistVisibility), nullable=False)
    shared_with: List[UUID] = Column(ARRAY(UUID), nullable=False)
    created_at: datetime = Column(DateTime(timezone=True), nullable=False)
    updated_at: datetime = Column(DateTime(timezone=True), nullable=False)
    version: int = Column(Integer, nullable=False, default=1)
    is_active: bool = Column(Boolean, default=True, nullable=False)

    def __init__(self, user_id: UUID, name: str, 
                 visibility: WishlistVisibility = WishlistVisibility.PRIVATE) -> None:
        """Initialize a new wishlist with validation."""
        if not isinstance(user_id, uuid.UUID):
            raise ValueError("Invalid user_id format")
        if not name or len(name) > 100:
            raise ValueError("Invalid name length or format")

        self.id = uuid.uuid4()
        self.user_id = user_id
        self.name = name
        self.items = []
        self.visibility = visibility
        self.shared_with = []
        self.created_at = datetime.now(timezone.utc)
        self.updated_at = self.created_at
        self.version = 1
        self.is_active = True

    def add_item(self, item: WishlistItem) -> bool:
        """Add a new item to the wishlist with validation."""
        if not isinstance(item, WishlistItem):
            raise ValueError("Invalid item type")
        
        if any(existing.product_id == item.product_id for existing in self.items):
            raise ValueError("Item already exists in wishlist")

        item.wishlist_id = self.id
        self.items.append(item)
        self.updated_at = datetime.now(timezone.utc)
        self.version += 1
        return True

    def share_with(self, user_ids: List[UUID]) -> bool:
        """Share wishlist with specified users with enhanced validation."""
        MAX_SHARE_USERS = 50

        if not all(isinstance(uid, uuid.UUID) for uid in user_ids):
            raise ValueError("Invalid user_id format in share list")
        
        if len(set(user_ids)) + len(self.shared_with) > MAX_SHARE_USERS:
            raise ValueError(f"Cannot share with more than {MAX_SHARE_USERS} users")

        self.shared_with.extend(user_ids)
        self.shared_with = list(set(self.shared_with))  # Remove duplicates
        self.visibility = WishlistVisibility.SHARED
        self.updated_at = datetime.now(timezone.utc)
        self.version += 1
        return True

    def to_dict(self, fields: Optional[List[str]] = None) -> Dict[str, Any]:
        """Convert wishlist to dictionary format with optional field filtering."""
        data = {
            'id': str(self.id),
            'user_id': str(self.user_id),
            'name': self.name,
            'items': [item.to_dict() for item in self.items],
            'visibility': self.visibility.value,
            'shared_with': [str(uid) for uid in self.shared_with],
            'created_at': self.created_at.isoformat(),
            'updated_at': self.updated_at.isoformat(),
            'version': self.version,
            'is_active': self.is_active
        }
        if fields:
            return {k: v for k, v in data.items() if k in fields}
        return data