"""
Payment Service Unit Tests
Version: 1.0
Description: Comprehensive test suite for payment processing with enhanced security validation
and PCI DSS compliance verification.

External Dependencies:
- pytest (7.4.x): Testing framework
- unittest.mock (python3.11+): Mocking functionality
- decimal (python3.11+): Precise decimal arithmetic
- uuid (python3.11+): UUID generation
- cryptography (41.0.x): Cryptographic operations
"""

import pytest
from unittest.mock import MagicMock, patch
from decimal import Decimal
import uuid
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.hmac import HMAC
from cryptography.hazmat.backends import default_backend

from ...src.services.payment import PaymentService
from ...src.models.purchase import Purchase, PurchaseStatus

# Test constants
TEST_PAYMENT_AMOUNT = Decimal('99.99')
TEST_CURRENCY = 'USD'
TEST_USER_ID = uuid.uuid4()
WEBHOOK_SECRET = 'whsec_test_12345'

# PCI-compliant test card numbers
PCI_TEST_CARDS = {
    'visa': '4242424242424242',
    'mastercard': '5555555555554444',
    'amex': '378282246310005'
}

@pytest.fixture
def mock_stripe_client():
    """Fixture for mocked Stripe client with security context."""
    with patch('stripe.PaymentIntent') as mock_intent:
        mock_intent.create.return_value = MagicMock(
            id='pi_test_123',
            client_secret='pi_test_secret',
            status='requires_payment_method'
        )
        yield mock_intent

@pytest.fixture
def mock_db_session():
    """Fixture for mocked database session with transaction support."""
    session = MagicMock()
    session.commit = MagicMock()
    session.rollback = MagicMock()
    return session

@pytest.fixture
def payment_service(mock_db_session):
    """Fixture for PaymentService instance with mocked dependencies."""
    return PaymentService(db_session=mock_db_session)

@pytest.mark.unit
@pytest.mark.security
async def test_create_payment_success(payment_service, mock_stripe_client, mock_db_session):
    """Test successful payment creation with security validation."""
    # Prepare test data with PCI-compliant card
    payment_metadata = {
        'card_type': 'visa',
        'last_four': '4242',
        'security_context': {
            'auth_method': '3d_secure',
            'risk_level': 'low'
        }
    }

    # Create payment with security context
    purchase = await payment_service.create_payment(
        user_id=TEST_USER_ID,
        amount=TEST_PAYMENT_AMOUNT,
        currency=TEST_CURRENCY,
        metadata=payment_metadata
    )

    # Verify Stripe API call with security parameters
    mock_stripe_client.create.assert_called_once()
    call_kwargs = mock_stripe_client.create.call_args[1]
    assert call_kwargs['amount'] == int(TEST_PAYMENT_AMOUNT * 100)
    assert call_kwargs['currency'] == TEST_CURRENCY.lower()
    assert call_kwargs['payment_method_options']['card']['request_three_d_secure'] == 'automatic'

    # Verify purchase record creation
    assert purchase.user_id == TEST_USER_ID
    assert purchase.amount == TEST_PAYMENT_AMOUNT
    assert purchase.currency == TEST_CURRENCY
    assert purchase.status == PurchaseStatus.PENDING
    assert purchase.stripe_payment_intent_id == 'pi_test_123'

    # Verify security metadata handling
    assert 'security_context' in purchase.metadata
    assert purchase.metadata['security_context']['auth_method'] == '3d_secure'
    assert 'card_type' in purchase.metadata
    assert 'last_four' in purchase.metadata

@pytest.mark.unit
@pytest.mark.security
async def test_create_payment_invalid_amount(payment_service):
    """Test payment creation with invalid amount validation."""
    with pytest.raises(ValueError) as exc_info:
        await payment_service.create_payment(
            user_id=TEST_USER_ID,
            amount=Decimal('-10.00'),
            currency=TEST_CURRENCY
        )
    assert "Payment amount must be greater than 0" in str(exc_info.value)

@pytest.mark.unit
@pytest.mark.security
async def test_create_payment_invalid_currency(payment_service):
    """Test payment creation with unsupported currency."""
    with pytest.raises(ValueError) as exc_info:
        await payment_service.create_payment(
            user_id=TEST_USER_ID,
            amount=TEST_PAYMENT_AMOUNT,
            currency='XXX'
        )
    assert "Currency XXX not supported" in str(exc_info.value)

@pytest.mark.unit
@pytest.mark.security
async def test_process_webhook_payment_success(payment_service, mock_db_session):
    """Test webhook processing with signature verification."""
    # Create mock webhook payload
    payload = '{"type": "payment_intent.succeeded", "data": {"object": {"id": "pi_test_123"}}}'
    
    # Generate test signature
    timestamp = int(1234567890)
    signed_payload = f"{timestamp}.{payload}"
    signature = generate_test_signature(signed_payload, WEBHOOK_SECRET)
    
    # Construct signature header
    sig_header = f"t={timestamp},v1={signature}"

    # Process webhook
    await payment_service.process_webhook(payload, sig_header)

    # Verify purchase status update
    mock_db_session.query.return_value.get.assert_called_once()
    purchase = mock_db_session.query.return_value.get.return_value
    assert purchase.status == PurchaseStatus.COMPLETED

@pytest.mark.unit
@pytest.mark.security
async def test_process_webhook_invalid_signature(payment_service):
    """Test webhook processing with invalid signature."""
    payload = '{"type": "payment_intent.succeeded"}'
    invalid_signature = 'invalid_signature'

    with pytest.raises(Exception) as exc_info:
        await payment_service.process_webhook(payload, invalid_signature)
    assert "Webhook signature verification failed" in str(exc_info.value)

@pytest.mark.unit
@pytest.mark.security
async def test_get_payment_status(payment_service, mock_db_session):
    """Test payment status retrieval with security context."""
    # Mock purchase record
    mock_purchase = MagicMock(
        id=uuid.uuid4(),
        status=PurchaseStatus.COMPLETED,
        stripe_payment_intent_id='pi_test_123',
        metadata={'security_context': {'auth_method': '3d_secure'}}
    )
    mock_db_session.query.return_value.get.return_value = mock_purchase

    # Get payment status
    status_info = await payment_service.get_payment_status(mock_purchase.id)

    # Verify status information
    assert status_info['status'] == PurchaseStatus.COMPLETED.value
    assert 'security_context' in status_info['metadata']
    assert status_info['metadata']['security_context']['auth_method'] == '3d_secure'

@pytest.mark.unit
@pytest.mark.security
async def test_refund_payment_success(payment_service, mock_stripe_client, mock_db_session):
    """Test successful payment refund with security validation."""
    # Mock purchase record
    mock_purchase = MagicMock(
        id=uuid.uuid4(),
        status=PurchaseStatus.COMPLETED,
        stripe_payment_intent_id='pi_test_123'
    )
    mock_db_session.query.return_value.get.return_value = mock_purchase

    # Process refund
    updated_purchase = await payment_service.refund_payment(mock_purchase.id)

    # Verify refund processing
    assert updated_purchase.status == PurchaseStatus.REFUNDED
    mock_stripe_client.refund_payment.assert_called_once_with(
        'pi_test_123',
        metadata={'purchase_id': str(mock_purchase.id)}
    )

def generate_test_signature(payload: str, secret: str) -> str:
    """Generate test webhook signature using HMAC."""
    hmac = HMAC(
        key=secret.encode(),
        algorithm=hashes.SHA256(),
        backend=default_backend()
    )
    hmac.update(payload.encode())
    return hmac.finalize().hex()