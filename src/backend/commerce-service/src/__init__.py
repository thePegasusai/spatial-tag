"""
Commerce Service Package Initializer
Version: 1.0.0
Description: Initializes the commerce service with secure payment processing,
logging configuration, and PCI DSS compliance measures.

External Dependencies:
- logging (python3.11+): Advanced logging configuration
- stripe (v5.4.0): PCI DSS compliant payment processing
- opentelemetry-api (v1.20.0): Distributed tracing
"""

import json
import logging
from logging.handlers import RotatingFileHandler
import stripe
from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode

from config.settings import (
    DatabaseConfig,
    STRIPE_API_KEY,
    STRIPE_WEBHOOK_SECRET
)

# Package version
__version__ = '1.0.0'

# Initialize tracer
tracer = trace.get_tracer('commerce_service')

# Initialize logger
logger = logging.getLogger('commerce_service')

@tracer.start_as_current_span('setup_logging')
def setup_logging(log_level: str = 'INFO') -> None:
    """Configure comprehensive logging with security event tracking.
    
    Args:
        log_level: Desired logging level (default: INFO)
    """
    # Configure JSON structured logging
    formatter = logging.Formatter(
        '{"timestamp":"%(asctime)s", "level":"%(levelname)s", '
        '"service":"commerce", "trace_id":"%(trace_id)s", '
        '"message":"%(message)s"}'
    )

    # Configure console handler
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    
    # Configure secure file handler with rotation
    file_handler = RotatingFileHandler(
        'logs/commerce_service.log',
        maxBytes=10485760,  # 10MB
        backupCount=30,     # 30 days retention for PCI DSS
        encoding='utf-8'
    )
    file_handler.setFormatter(formatter)

    # Configure security event handler
    security_handler = RotatingFileHandler(
        'logs/security_events.log',
        maxBytes=10485760,
        backupCount=90,     # 90 days retention for security events
        encoding='utf-8'
    )
    security_handler.setFormatter(formatter)
    security_handler.addFilter(lambda record: 'security' in record.getMessage().lower())

    # Set logging level
    logger.setLevel(getattr(logging, log_level.upper()))
    
    # Add handlers
    logger.addHandler(console_handler)
    logger.addHandler(file_handler)
    logger.addHandler(security_handler)
    
    # Suppress external library logging
    logging.getLogger('stripe').setLevel(logging.WARNING)
    logging.getLogger('urllib3').setLevel(logging.WARNING)

@tracer.start_as_current_span('init_stripe')
def init_stripe() -> None:
    """Initialize Stripe with PCI DSS compliant configuration."""
    try:
        # Configure Stripe with API key
        stripe.api_key = STRIPE_API_KEY
        stripe.api_version = '2023-10-16'  # Lock API version
        stripe.max_network_retries = 2
        stripe.verify_ssl_certs = True
        
        # Configure webhook signing
        stripe.webhook.webhook_secret = STRIPE_WEBHOOK_SECRET
        
        # Configure automatic timeout
        stripe.default_http_client = stripe.http_client.RequestsClient(
            timeout=30,
            verify_ssl_certs=True
        )
        
        logger.info('Stripe initialized successfully', extra={'security': True})
    except Exception as e:
        logger.error(f'Failed to initialize Stripe: {str(e)}', 
                    extra={'security': True})
        raise

@tracer.start_as_current_span('init_service')
def init_service() -> bool:
    """Initialize the commerce service with all required components.
    
    Returns:
        bool: True if initialization successful, False otherwise
    """
    try:
        # Setup logging first
        setup_logging()
        logger.info('Starting commerce service initialization')
        
        # Initialize Stripe
        init_stripe()
        
        # Validate database configuration
        db_config = DatabaseConfig()
        if not db_config.DB_SSL_REQUIRED:
            logger.warning('Database SSL is not enabled', extra={'security': True})
        
        # Log successful initialization
        logger.info('Commerce service initialized successfully')
        return True
        
    except Exception as e:
        logger.error(f'Failed to initialize commerce service: {str(e)}',
                    extra={'security': True})
        return False

# Initialize service on module import
init_service()