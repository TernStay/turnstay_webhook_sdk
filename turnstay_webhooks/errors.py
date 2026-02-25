class WebhookError(Exception):
    """Base exception for all webhook SDK errors."""


class WebhookClientError(WebhookError):
    """Raised when the webhook client encounters an error emitting events."""


class SignatureVerificationError(WebhookError):
    """Raised when webhook signature verification fails."""


class TimestampTooOldError(WebhookError):
    """Raised when the webhook timestamp exceeds the allowed tolerance (replay protection)."""
