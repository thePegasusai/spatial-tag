"""
Integration tests for wishlist functionality in the commerce service.
Tests wishlist creation, management, sharing capabilities, and performance metrics.

External Dependencies:
pytest==7.4.x
freezegun==1.2.x
prometheus_client==0.17.x
"""

import asyncio
import uuid
from decimal import Decimal
from datetime import datetime, timezone
import pytest
from freezegun import freeze_time
from prometheus_client import REGISTRY

from ...src.services.wishlist import WishlistService
from ...src.models.wishlist import Wishlist, WishlistVisibility

# Test constants
TEST_ITEM_DATA = {
    'product_id': str(uuid.uuid4()),
    'name': 'Test Product',
    'price': Decimal('99.99'),
    'currency': 'USD',
    'image_url': 'https://example.com/test.jpg',
    'metadata': {
        'version': 1,
        'created_at': datetime.now(timezone.utc),
        'tags': ['test', 'integration']
    }
}

PERFORMANCE_THRESHOLDS = {
    'create_wishlist_ms': 100,
    'update_wishlist_ms': 50,
    'share_wishlist_ms': 75
}

@pytest.fixture
def wishlist_service(db_session):
    """Create a WishlistService instance for testing."""
    return WishlistService(db_session)

@pytest.fixture
def sample_wishlist(wishlist_service):
    """Create a sample wishlist for testing."""
    user_id = uuid.uuid4()
    wishlist = wishlist_service.create_wishlist(
        user_id=user_id,
        name="Test Wishlist",
        visibility=WishlistVisibility.PRIVATE
    )
    return wishlist

@pytest.mark.integration
def test_create_wishlist(wishlist_service):
    """Test successful wishlist creation with performance validation."""
    # Arrange
    user_id = uuid.uuid4()
    wishlist_name = "My Shopping List"
    start_time = datetime.now(timezone.utc)

    # Act
    wishlist = wishlist_service.create_wishlist(
        user_id=user_id,
        name=wishlist_name,
        visibility=WishlistVisibility.PRIVATE
    )

    # Assert - Basic properties
    assert wishlist is not None
    assert isinstance(wishlist.id, uuid.UUID)
    assert wishlist.user_id == user_id
    assert wishlist.name == wishlist_name
    assert wishlist.visibility == WishlistVisibility.PRIVATE
    assert wishlist.version == 1
    assert wishlist.is_active is True

    # Assert - Performance
    execution_time = (datetime.now(timezone.utc) - start_time).total_seconds() * 1000
    assert execution_time < PERFORMANCE_THRESHOLDS['create_wishlist_ms']

@pytest.mark.integration
def test_add_item_to_wishlist(wishlist_service, sample_wishlist):
    """Test adding items to wishlist with validation."""
    # Act
    wishlist, item = wishlist_service.add_wishlist_item(
        wishlist_id=sample_wishlist.id,
        item_data=TEST_ITEM_DATA
    )

    # Assert
    assert len(wishlist.items) == 1
    assert item.product_id == TEST_ITEM_DATA['product_id']
    assert item.price == TEST_ITEM_DATA['price']
    assert wishlist.version == 2

@pytest.mark.integration
def test_share_wishlist(wishlist_service, sample_wishlist):
    """Test wishlist sharing functionality with performance metrics."""
    # Arrange
    share_users = [uuid.uuid4() for _ in range(3)]
    start_time = datetime.now(timezone.utc)

    # Act
    updated_wishlist = wishlist_service.share_wishlist(
        wishlist_id=sample_wishlist.id,
        user_ids=share_users
    )

    # Assert - Sharing logic
    assert updated_wishlist.visibility == WishlistVisibility.SHARED
    assert len(updated_wishlist.shared_with) == 3
    assert all(user_id in updated_wishlist.shared_with for user_id in share_users)
    assert updated_wishlist.version > sample_wishlist.version

    # Assert - Performance
    execution_time = (datetime.now(timezone.utc) - start_time).total_seconds() * 1000
    assert execution_time < PERFORMANCE_THRESHOLDS['share_wishlist_ms']

@pytest.mark.integration
@pytest.mark.asyncio
async def test_concurrent_item_updates(wishlist_service, sample_wishlist):
    """Test concurrent item updates to wishlist with version control."""
    # Arrange
    items_to_add = [
        {**TEST_ITEM_DATA, 'product_id': str(uuid.uuid4())} 
        for _ in range(5)
    ]
    
    async def add_item(item_data):
        return wishlist_service.add_wishlist_item(
            wishlist_id=sample_wishlist.id,
            item_data=item_data
        )

    # Act
    tasks = [add_item(item) for item in items_to_add]
    results = await asyncio.gather(*tasks, return_exceptions=True)

    # Assert
    successful_updates = [r for r in results if not isinstance(r, Exception)]
    assert len(successful_updates) == 5
    
    final_wishlist = wishlist_service.get_wishlist(sample_wishlist.id)
    assert len(final_wishlist.items) == 5
    assert final_wishlist.version == sample_wishlist.version + 5

@pytest.mark.integration
def test_wishlist_version_control(wishlist_service, sample_wishlist):
    """Test optimistic locking with wishlist version control."""
    # Arrange
    original_version = sample_wishlist.version

    # Act
    wishlist_service.update_wishlist(
        wishlist_id=sample_wishlist.id,
        updates={'name': 'Updated Wishlist'}
    )

    # Assert
    updated_wishlist = wishlist_service.get_wishlist(sample_wishlist.id)
    assert updated_wishlist.version == original_version + 1
    assert updated_wishlist.name == 'Updated Wishlist'

@pytest.mark.integration
def test_wishlist_metrics(wishlist_service):
    """Test wishlist performance metrics collection."""
    # Arrange
    initial_metrics = {
        'wishlist_creation_seconds': REGISTRY.get_sample_value(
            'wishlist_creation_seconds_count'
        ) or 0
    }

    # Act
    wishlist = wishlist_service.create_wishlist(
        user_id=uuid.uuid4(),
        name="Metrics Test Wishlist"
    )

    # Assert
    final_metrics = {
        'wishlist_creation_seconds': REGISTRY.get_sample_value(
            'wishlist_creation_seconds_count'
        ) or 0
    }
    assert final_metrics['wishlist_creation_seconds'] > initial_metrics['wishlist_creation_seconds']

@pytest.mark.integration
def test_wishlist_cleanup(wishlist_service, sample_wishlist):
    """Test wishlist cleanup and soft deletion."""
    # Act
    wishlist_service.update_wishlist(
        wishlist_id=sample_wishlist.id,
        updates={'is_active': False}
    )

    # Assert
    inactive_wishlist = wishlist_service.get_wishlist(sample_wishlist.id)
    assert inactive_wishlist is None

@pytest.mark.integration
def test_max_items_validation(wishlist_service, sample_wishlist):
    """Test wishlist item limit validation."""
    # Arrange
    MAX_ITEMS = 50
    items = [
        {**TEST_ITEM_DATA, 'product_id': str(uuid.uuid4())}
        for _ in range(MAX_ITEMS + 1)
    ]

    # Act & Assert
    for i, item in enumerate(items):
        if i < MAX_ITEMS:
            wishlist_service.add_wishlist_item(sample_wishlist.id, item)
        else:
            with pytest.raises(ValueError, match="Maximum items limit reached"):
                wishlist_service.add_wishlist_item(sample_wishlist.id, item)

@pytest.mark.integration
@freeze_time("2024-01-01 12:00:00")
def test_wishlist_timestamps(wishlist_service):
    """Test wishlist timestamp handling and updates."""
    # Act
    wishlist = wishlist_service.create_wishlist(
        user_id=uuid.uuid4(),
        name="Timestamp Test"
    )

    # Assert
    assert wishlist.created_at.isoformat() == "2024-01-01T12:00:00+00:00"
    assert wishlist.updated_at.isoformat() == "2024-01-01T12:00:00+00:00"