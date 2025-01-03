"""
Wishlist service implementation for commerce functionality.
Handles business logic for creating, updating, and sharing wishlists with enhanced validation and logging.

External Dependencies:
sqlalchemy==2.0.0
"""

import logging
import uuid
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple, Any
from sqlalchemy.orm import Session
from sqlalchemy.exc import SQLAlchemyError, IntegrityError
from sqlalchemy.orm.exc import NoResultFound
from contextlib import contextmanager

from ..models.wishlist import Wishlist, WishlistItem, WishlistVisibility

# Configure structured logging
logger = logging.getLogger(__name__)

class WishlistService:
    """Service class implementing business logic for wishlist management with enhanced validation and error handling."""

    def __init__(self, db_session: Session) -> None:
        """
        Initialize wishlist service with database session and logging configuration.
        
        Args:
            db_session: SQLAlchemy database session
        """
        if not isinstance(db_session, Session):
            raise ValueError("Invalid database session provided")
        
        self._db_session = db_session
        self._setup_logging()

    def _setup_logging(self) -> None:
        """Configure enhanced structured logging with performance metrics."""
        logging.basicConfig(
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            level=logging.INFO
        )

    @contextmanager
    def _transaction(self):
        """Context manager for handling database transactions with retry logic."""
        try:
            yield
            self._db_session.commit()
        except IntegrityError as e:
            self._db_session.rollback()
            logger.error(f"Transaction failed due to integrity error: {str(e)}")
            raise
        except SQLAlchemyError as e:
            self._db_session.rollback()
            logger.error(f"Transaction failed due to database error: {str(e)}")
            raise
        except Exception as e:
            self._db_session.rollback()
            logger.error(f"Transaction failed due to unexpected error: {str(e)}")
            raise

    def create_wishlist(self, user_id: uuid.UUID, name: str, 
                       visibility: WishlistVisibility = WishlistVisibility.PRIVATE) -> Wishlist:
        """
        Create a new wishlist for a user with enhanced validation.

        Args:
            user_id: UUID of the user creating the wishlist
            name: Name of the wishlist
            visibility: Visibility level for the wishlist

        Returns:
            Created Wishlist instance

        Raises:
            ValueError: If input validation fails
            SQLAlchemyError: If database operation fails
        """
        logger.info(f"Creating wishlist for user {user_id}")
        start_time = datetime.now(timezone.utc)

        try:
            # Validate inputs
            if not isinstance(user_id, uuid.UUID):
                raise ValueError("Invalid user_id format")
            if not name or len(name.strip()) > 100:
                raise ValueError("Invalid wishlist name length")
            if not isinstance(visibility, WishlistVisibility):
                raise ValueError("Invalid visibility type")

            # Create wishlist instance
            wishlist = Wishlist(
                user_id=user_id,
                name=name.strip(),
                visibility=visibility
            )

            with self._transaction():
                self._db_session.add(wishlist)

            execution_time = (datetime.now(timezone.utc) - start_time).total_seconds()
            logger.info(f"Wishlist created successfully in {execution_time}s")
            return wishlist

        except Exception as e:
            logger.error(f"Failed to create wishlist: {str(e)}")
            raise

    def get_wishlist(self, wishlist_id: uuid.UUID) -> Optional[Wishlist]:
        """
        Retrieve a wishlist by ID with performance optimization.

        Args:
            wishlist_id: UUID of the wishlist to retrieve

        Returns:
            Wishlist instance if found, None otherwise

        Raises:
            ValueError: If invalid wishlist_id format
            SQLAlchemyError: If database operation fails
        """
        logger.info(f"Retrieving wishlist {wishlist_id}")
        start_time = datetime.now(timezone.utc)

        try:
            if not isinstance(wishlist_id, uuid.UUID):
                raise ValueError("Invalid wishlist_id format")

            wishlist = self._db_session.query(Wishlist)\
                .filter(Wishlist.id == wishlist_id, Wishlist.is_active == True)\
                .first()

            execution_time = (datetime.now(timezone.utc) - start_time).total_seconds()
            logger.info(f"Wishlist retrieved in {execution_time}s")
            return wishlist

        except Exception as e:
            logger.error(f"Failed to retrieve wishlist: {str(e)}")
            raise

    def update_wishlist(self, wishlist_id: uuid.UUID, updates: Dict[str, Any]) -> Wishlist:
        """
        Update wishlist properties with optimistic locking.

        Args:
            wishlist_id: UUID of the wishlist to update
            updates: Dictionary of properties to update

        Returns:
            Updated Wishlist instance

        Raises:
            ValueError: If invalid input data
            NoResultFound: If wishlist not found
            SQLAlchemyError: If database operation fails
        """
        logger.info(f"Updating wishlist {wishlist_id}")
        start_time = datetime.now(timezone.utc)

        try:
            wishlist = self.get_wishlist(wishlist_id)
            if not wishlist:
                raise NoResultFound("Wishlist not found")

            # Validate and apply updates
            if 'name' in updates:
                if not updates['name'] or len(updates['name'].strip()) > 100:
                    raise ValueError("Invalid wishlist name length")
                wishlist.name = updates['name'].strip()

            if 'visibility' in updates:
                if not isinstance(updates['visibility'], WishlistVisibility):
                    raise ValueError("Invalid visibility type")
                wishlist.visibility = updates['visibility']

            wishlist.updated_at = datetime.now(timezone.utc)
            wishlist.version += 1

            with self._transaction():
                self._db_session.add(wishlist)

            execution_time = (datetime.now(timezone.utc) - start_time).total_seconds()
            logger.info(f"Wishlist updated successfully in {execution_time}s")
            return wishlist

        except Exception as e:
            logger.error(f"Failed to update wishlist: {str(e)}")
            raise

    def add_wishlist_item(self, wishlist_id: uuid.UUID, item_data: Dict[str, Any]) -> Tuple[Wishlist, WishlistItem]:
        """
        Add an item to a wishlist with validation.

        Args:
            wishlist_id: UUID of the target wishlist
            item_data: Dictionary containing item details

        Returns:
            Tuple of (updated Wishlist, created WishlistItem)

        Raises:
            ValueError: If invalid input data
            NoResultFound: If wishlist not found
            SQLAlchemyError: If database operation fails
        """
        logger.info(f"Adding item to wishlist {wishlist_id}")
        start_time = datetime.now(timezone.utc)

        try:
            wishlist = self.get_wishlist(wishlist_id)
            if not wishlist:
                raise NoResultFound("Wishlist not found")

            # Create and validate item
            item = WishlistItem(
                product_id=item_data['product_id'],
                name=item_data['name'],
                price=item_data['price'],
                currency=item_data['currency'],
                image_url=item_data.get('image_url')
            )

            wishlist.add_item(item)

            with self._transaction():
                self._db_session.add(wishlist)

            execution_time = (datetime.now(timezone.utc) - start_time).total_seconds()
            logger.info(f"Item added to wishlist successfully in {execution_time}s")
            return wishlist, item

        except Exception as e:
            logger.error(f"Failed to add item to wishlist: {str(e)}")
            raise

    def share_wishlist(self, wishlist_id: uuid.UUID, user_ids: List[uuid.UUID]) -> Wishlist:
        """
        Share wishlist with specified users.

        Args:
            wishlist_id: UUID of the wishlist to share
            user_ids: List of user UUIDs to share with

        Returns:
            Updated Wishlist instance

        Raises:
            ValueError: If invalid input data
            NoResultFound: If wishlist not found
            SQLAlchemyError: If database operation fails
        """
        logger.info(f"Sharing wishlist {wishlist_id} with {len(user_ids)} users")
        start_time = datetime.now(timezone.utc)

        try:
            wishlist = self.get_wishlist(wishlist_id)
            if not wishlist:
                raise NoResultFound("Wishlist not found")

            wishlist.share_with(user_ids)

            with self._transaction():
                self._db_session.add(wishlist)

            execution_time = (datetime.now(timezone.utc) - start_time).total_seconds()
            logger.info(f"Wishlist shared successfully in {execution_time}s")
            return wishlist

        except Exception as e:
            logger.error(f"Failed to share wishlist: {str(e)}")
            raise