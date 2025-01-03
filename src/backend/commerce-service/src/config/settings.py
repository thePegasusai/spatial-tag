"""
Commerce Service Configuration Settings
Version: 1.0
Description: Secure configuration management for payment processing, wishlist features,
and service parameters with PCI DSS compliance focus.

External Dependencies:
- os (python3.11+): Environment variable access and validation
- typing (python3.11+): Type hints for configuration parameters
- dataclasses (python3.11+): Configuration class definitions
- logging (python3.11+): Configuration logging
"""

import os
import logging
from typing import List, Optional
from dataclasses import dataclass

# Global Environment Settings
ENV = os.getenv('APP_ENV', 'development')
DEBUG = os.getenv('DEBUG', 'False').lower() == 'true'
LOG_LEVEL = logging.DEBUG if DEBUG else logging.INFO

# Configure logging
logging.basicConfig(
    level=LOG_LEVEL,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class DatabaseConfig:
    """Secure database configuration management with connection pooling"""
    DB_HOST: str
    DB_PORT: str
    DB_NAME: str
    DB_USER: str
    DB_PASSWORD: str
    DB_POOL_SIZE: int
    DB_MAX_OVERFLOW: int
    DB_POOL_TIMEOUT: float
    DB_SSL_REQUIRED: bool

    def __init__(self):
        """Initialize database configuration with secure defaults"""
        self.DB_HOST = os.getenv('DB_HOST')
        self.DB_PORT = os.getenv('DB_PORT', '5432')
        self.DB_NAME = os.getenv('DB_NAME')
        self.DB_USER = os.getenv('DB_USER')
        self.DB_PASSWORD = os.getenv('DB_PASSWORD')
        self.DB_POOL_SIZE = int(os.getenv('DB_POOL_SIZE', '10'))
        self.DB_MAX_OVERFLOW = int(os.getenv('DB_MAX_OVERFLOW', '20'))
        self.DB_POOL_TIMEOUT = float(os.getenv('DB_POOL_TIMEOUT', '30.0'))
        self.DB_SSL_REQUIRED = ENV != 'development'

        if not all([self.DB_HOST, self.DB_NAME, self.DB_USER, self.DB_PASSWORD]):
            raise ValueError("Missing required database configuration parameters")

    def get_connection_url(self) -> str:
        """Generate secure database connection URL with credentials"""
        ssl_params = "?sslmode=require" if self.DB_SSL_REQUIRED else ""
        return (
            f"postgresql://{self.DB_USER}:{self.DB_PASSWORD}@"
            f"{self.DB_HOST}:{self.DB_PORT}/{self.DB_NAME}{ssl_params}"
        )

@dataclass
class StripeConfig:
    """PCI DSS compliant Stripe payment configuration"""
    API_KEY: str
    WEBHOOK_SECRET: str
    ENDPOINT_SECRET: str
    USE_3D_SECURE: bool
    PAYMENT_TIMEOUT: int
    ALLOWED_CURRENCIES: List[str]

    def __init__(self):
        """Initialize Stripe configuration with security validation"""
        self.API_KEY = os.getenv('STRIPE_API_KEY')
        self.WEBHOOK_SECRET = os.getenv('STRIPE_WEBHOOK_SECRET')
        self.ENDPOINT_SECRET = os.getenv('STRIPE_ENDPOINT_SECRET')
        self.USE_3D_SECURE = True  # Required for PCI DSS compliance
        self.PAYMENT_TIMEOUT = int(os.getenv('PAYMENT_TIMEOUT', '300'))  # 5 minutes
        self.ALLOWED_CURRENCIES = ['USD', 'EUR', 'GBP']  # Supported currencies

        if not all([self.API_KEY, self.WEBHOOK_SECRET, self.ENDPOINT_SECRET]):
            raise ValueError("Missing required Stripe configuration parameters")

def load_stripe_config() -> StripeConfig:
    """Securely load and validate Stripe configuration"""
    try:
        config = StripeConfig()
        logger.info("Stripe configuration loaded successfully")
        return config
    except ValueError as e:
        logger.error(f"Failed to load Stripe configuration: {str(e)}")
        raise

def validate_environment() -> bool:
    """Validate all required environment variables"""
    required_vars = [
        'DB_HOST',
        'DB_NAME',
        'DB_USER',
        'DB_PASSWORD',
        'STRIPE_API_KEY',
        'STRIPE_WEBHOOK_SECRET',
        'STRIPE_ENDPOINT_SECRET'
    ]

    missing_vars = [var for var in required_vars if not os.getenv(var)]
    
    if missing_vars:
        logger.error(f"Missing required environment variables: {', '.join(missing_vars)}")
        return False
    
    logger.info("Environment validation successful")
    return True

# Initialize configurations
DATABASE_CONFIG = DatabaseConfig()
STRIPE_CONFIG = load_stripe_config()

# Wishlist feature configuration
WISHLIST_SETTINGS = {
    'ITEM_LIMIT': int(os.getenv('WISHLIST_ITEM_LIMIT', '50')),
    'SHARING_ENABLED': os.getenv('WISHLIST_SHARING_ENABLED', 'True').lower() == 'true',
    'MAX_SHARED_USERS': int(os.getenv('WISHLIST_MAX_SHARED_USERS', '5')),
    'ITEM_PRICE_LIMIT': float(os.getenv('WISHLIST_ITEM_PRICE_LIMIT', '10000.0')),
    'ALLOWED_ITEM_TYPES': ['product', 'experience', 'service']
}

# Security settings
SECURITY_SETTINGS = {
    'SESSION_TIMEOUT': int(os.getenv('SESSION_TIMEOUT', '3600')),  # 1 hour
    'MAX_LOGIN_ATTEMPTS': int(os.getenv('MAX_LOGIN_ATTEMPTS', '5')),
    'PASSWORD_EXPIRY_DAYS': int(os.getenv('PASSWORD_EXPIRY_DAYS', '90')),
    'REQUIRE_2FA': ENV == 'production'
}

# Validate environment on module load
if not validate_environment():
    raise RuntimeError("Failed to validate environment configuration")