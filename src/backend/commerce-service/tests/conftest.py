"""
Pytest fixtures configuration for commerce service tests
Version: 1.0
Description: Test fixtures providing isolated database sessions and mock objects
for secure payment processing and collaborative shopping features testing.

External Dependencies:
- pytest==7.4.x: Testing framework
- sqlalchemy==2.0.x: Database session management
- unittest.mock: Mocking framework
"""

import uuid
from datetime import datetime, timezone
from decimal import Decimal
from typing import Generator
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from unittest.mock import MagicMock, PropertyMock

from ..src.models.purchase import Purchase, PurchaseStatus, PurchaseType
from ..src.models.wishlist import Wishlist, WishlistVisibility, WishlistItem
from ..src.services.stripe_client import StripeClient

# Test constants with secure defaults
TEST_USER_ID = uuid.uuid4()
TEST_PRODUCT_ID = uuid.uuid4()
TEST_STRIPE_KEY = 'sk_test_sample'
TEST_WEBHOOK_SECRET = 'whsec_sample'

@pytest.fixture(scope='function')
def db_session() -> Generator[Session, None, None]:
    """
    Provides an isolated database session for tests with automatic cleanup.
    
    Returns:
        Generator[Session]: SQLAlchemy session with transaction isolation
    """
    # Create test database engine with high isolation level
    engine = create_engine(
        'postgresql://test:test@localhost/test_db',
        isolation_level='SERIALIZABLE',
        pool_pre_ping=True
    )
    
    # Create test schema and tables
    from ..src.models.purchase import Base as PurchaseBase
    from ..src.models.wishlist import Base as WishlistBase
    
    PurchaseBase.metadata.create_all(engine)
    WishlistBase.metadata.create_all(engine)
    
    # Create session factory
    TestingSessionLocal = sessionmaker(
        bind=engine,
        autocommit=False,
        autoflush=False,
        expire_on_commit=False
    )
    
    # Create new session
    session = TestingSessionLocal()
    
    try:
        # Begin nested transaction
        session.begin_nested()
        yield session
        
    finally:
        # Rollback and cleanup
        session.rollback()
        session.close()
        # Drop test tables
        PurchaseBase.metadata.drop_all(engine)
        WishlistBase.metadata.drop_all(engine)

@pytest.fixture(scope='function')
def mock_stripe_client() -> MagicMock:
    """
    Provides a PCI-compliant mocked Stripe client for payment testing.
    
    Returns:
        MagicMock: Mocked StripeClient instance with security features
    """
    mock_client = MagicMock(spec=StripeClient)
    
    # Configure payment intent mock
    mock_payment_intent = MagicMock()
    mock_payment_intent.id = f'pi_test_{uuid.uuid4()}'
    mock_payment_intent.client_secret = f'pi_test_secret_{uuid.uuid4()}'
    mock_payment_intent.status = 'requires_confirmation'
    mock_payment_intent.next_action = {
        'type': 'use_stripe_sdk',
        'use_stripe_sdk': {'type': '3d_secure_redirect'}
    }
    
    # Setup create_payment_intent mock
    mock_client.create_payment_intent.return_value = mock_payment_intent
    
    # Configure webhook verification mock
    mock_event = MagicMock()
    mock_event.type = 'payment_intent.succeeded'
    mock_event.data.object = mock_payment_intent
    
    mock_client.verify_webhook.return_value = mock_event
    
    return mock_client

@pytest.fixture(scope='function')
def sample_purchase(db_session: Session) -> Purchase:
    """
    Provides a sample purchase record with collaborative features.
    
    Args:
        db_session: SQLAlchemy session fixture
        
    Returns:
        Purchase: Sample purchase record
    """
    purchase = Purchase(
        user_id=TEST_USER_ID,
        amount=Decimal('99.99'),
        currency='USD',
        stripe_payment_intent_id=f'pi_test_{uuid.uuid4()}',
        metadata={
            'product_name': 'Test Product',
            'category': 'Test Category'
        },
        collaborative_data={
            'shared_users': [str(uuid.uuid4()) for _ in range(2)],
            'shared_items': ['item1', 'item2'],
            'total_participants': 3,
            'sharing_enabled': True
        }
    )
    
    db_session.add(purchase)
    db_session.commit()
    
    return purchase

@pytest.fixture(scope='function')
def sample_wishlist(db_session: Session) -> Wishlist:
    """
    Provides a sample wishlist with enhanced sharing capabilities.
    
    Args:
        db_session: SQLAlchemy session fixture
        
    Returns:
        Wishlist: Sample wishlist with collaboration features
    """
    wishlist = Wishlist(
        user_id=TEST_USER_ID,
        name='Test Wishlist',
        visibility=WishlistVisibility.SHARED
    )
    
    # Add sample items
    items = [
        WishlistItem(
            product_id=str(TEST_PRODUCT_ID),
            name='Test Product 1',
            price=Decimal('49.99'),
            currency='USD',
            image_url='https://example.com/image1.jpg'
        ),
        WishlistItem(
            product_id=str(uuid.uuid4()),
            name='Test Product 2',
            price=Decimal('99.99'),
            currency='USD',
            image_url='https://example.com/image2.jpg'
        )
    ]
    
    for item in items:
        wishlist.add_item(item)
    
    # Share with test users
    shared_users = [uuid.uuid4() for _ in range(2)]
    wishlist.share_with(shared_users)
    
    db_session.add(wishlist)
    db_session.commit()
    
    return wishlist