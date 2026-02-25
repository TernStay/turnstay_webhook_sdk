import hashlib
import hmac
import json
import time

import pytest

from turnstay_webhooks.errors import SignatureVerificationError, TimestampTooOldError
from turnstay_webhooks.signature import WebhookSignature


def _sign(secret: str, payload: str, timestamp: str | None = None) -> str:
    ts = timestamp or str(int(time.time()))
    to_sign = f"{ts}.{payload}"
    sig = hmac.new(
        secret.encode("utf-8"),
        to_sign.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    return f"t={ts}, v1={sig}"


class TestWebhookSignature:
    SECRET = "whsec_test_secret_123"
    PAYLOAD = json.dumps({"type": "payment_intent.succeeded", "data": {"object": {"id": "pi_1"}}})

    def test_valid_signature(self):
        header = _sign(self.SECRET, self.PAYLOAD)
        result = WebhookSignature.verify(self.PAYLOAD, header, self.SECRET)
        assert result["type"] == "payment_intent.succeeded"

    def test_valid_signature_bytes(self):
        header = _sign(self.SECRET, self.PAYLOAD)
        result = WebhookSignature.verify(self.PAYLOAD.encode("utf-8"), header, self.SECRET)
        assert result["type"] == "payment_intent.succeeded"

    def test_invalid_signature_raises(self):
        ts = str(int(time.time()))
        header = f"t={ts}, v1=bad_signature_value"
        with pytest.raises(SignatureVerificationError):
            WebhookSignature.verify(self.PAYLOAD, header, self.SECRET)

    def test_wrong_secret_raises(self):
        header = _sign(self.SECRET, self.PAYLOAD)
        with pytest.raises(SignatureVerificationError):
            WebhookSignature.verify(self.PAYLOAD, header, "wrong_secret")

    def test_old_timestamp_raises(self):
        old_ts = str(int(time.time()) - 600)
        header = _sign(self.SECRET, self.PAYLOAD, timestamp=old_ts)
        with pytest.raises(TimestampTooOldError):
            WebhookSignature.verify(self.PAYLOAD, header, self.SECRET, tolerance=300)

    def test_missing_timestamp_raises(self):
        header = "v1=somesig"
        with pytest.raises(SignatureVerificationError, match="Missing timestamp"):
            WebhookSignature.verify(self.PAYLOAD, header, self.SECRET)

    def test_missing_v1_raises(self):
        header = "t=12345"
        with pytest.raises(SignatureVerificationError, match="No v1 signature"):
            WebhookSignature.verify(self.PAYLOAD, header, self.SECRET)

    def test_tolerance_zero_skips_check(self):
        old_ts = str(int(time.time()) - 99999)
        header = _sign(self.SECRET, self.PAYLOAD, timestamp=old_ts)
        result = WebhookSignature.verify(self.PAYLOAD, header, self.SECRET, tolerance=0)
        assert result["type"] == "payment_intent.succeeded"
