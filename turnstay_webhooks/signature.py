import hashlib
import hmac
import json
import time

from .errors import SignatureVerificationError, TimestampTooOldError

DEFAULT_TOLERANCE = 300  # 5 minutes


class WebhookSignature:
    """Utility for verifying TurnStay webhook signatures.

    Usage:
        WebhookSignature.verify(payload, sig_header, secret)
    """

    SignatureVerificationError = SignatureVerificationError
    TimestampTooOldError = TimestampTooOldError

    @staticmethod
    def verify(
        payload: bytes | str,
        signature_header: str,
        secret: str,
        tolerance: int = DEFAULT_TOLERANCE,
    ) -> dict:
        """Verify a webhook signature and return the parsed payload.

        Args:
            payload: Raw request body (bytes or string).
            signature_header: Value of the Turnstay-Signature header.
            secret: Your webhook endpoint secret (whsec_...).
            tolerance: Maximum age of the timestamp in seconds (default 300).

        Returns:
            Parsed JSON payload as a dict.

        Raises:
            SignatureVerificationError: If the signature doesn't match.
            TimestampTooOldError: If the timestamp is outside the tolerance window.
        """
        if isinstance(payload, bytes):
            payload_str = payload.decode("utf-8")
        else:
            payload_str = payload

        timestamp, signatures = WebhookSignature._parse_header(signature_header)

        if tolerance > 0:
            age = abs(time.time() - int(timestamp))
            if age > tolerance:
                raise TimestampTooOldError(
                    f"Timestamp is {int(age)}s old, exceeds tolerance of {tolerance}s"
                )

        expected = WebhookSignature._compute_signature(secret, timestamp, payload_str)

        matched = any(hmac.compare_digest(expected, sig) for sig in signatures)
        if not matched:
            raise SignatureVerificationError("No matching signature found")

        return json.loads(payload_str)

    @staticmethod
    def _parse_header(header: str) -> tuple[str, list[str]]:
        """Parse the Turnstay-Signature header into timestamp and signature list."""
        timestamp = None
        signatures = []

        for item in header.split(","):
            item = item.strip()
            if "=" not in item:
                continue
            key, value = item.split("=", 1)
            key = key.strip()
            value = value.strip()

            if key == "t":
                timestamp = value
            elif key == "v1":
                signatures.append(value)

        if timestamp is None:
            raise SignatureVerificationError("Missing timestamp in signature header")
        if not signatures:
            raise SignatureVerificationError("No v1 signature found in header")

        return timestamp, signatures

    @staticmethod
    def _compute_signature(secret: str, timestamp: str, payload: str) -> str:
        """Compute HMAC-SHA256 signature matching the webhook-service's signing logic."""
        to_sign = f"{timestamp}.{payload}"
        return hmac.new(
            secret.encode("utf-8"),
            to_sign.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()
