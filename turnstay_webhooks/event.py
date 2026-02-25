from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from .signature import WebhookSignature


@dataclass
class EventData:
    """Represents the data payload of a webhook event."""

    object: dict[str, Any] = field(default_factory=dict)
    previous_attributes: dict[str, Any] | None = None

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> EventData:
        return cls(
            object=d.get("object", {}),
            previous_attributes=d.get("previous_attributes"),
        )


@dataclass
class Event:
    """Represents a TurnStay webhook event.

    Usage:
        event = Event.construct_from(payload, signature, secret)

        match event.type:
            case "payment_intent.succeeded":
                pi = event.data.object
                print(f"Payment {pi['id']} succeeded")
    """

    id: str
    type: str
    created_at: str | None
    api_version: str | None
    data: EventData

    @classmethod
    def construct_from(
        cls,
        payload: bytes | str,
        signature: str,
        secret: str,
        tolerance: int = 300,
    ) -> Event:
        """Verify signature and construct an Event from the raw payload.

        Args:
            payload: Raw request body.
            signature: Value of the Turnstay-Signature header.
            secret: Your endpoint secret (whsec_...).
            tolerance: Max timestamp age in seconds.

        Returns:
            An Event instance with verified, parsed data.

        Raises:
            SignatureVerificationError: If signature doesn't match.
            TimestampTooOldError: If timestamp is too old.
        """
        parsed = WebhookSignature.verify(payload, signature, secret, tolerance)
        return cls.from_dict(parsed)

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> Event:
        """Construct an Event from a parsed dict (no signature verification)."""
        data_raw = d.get("data", {})
        if isinstance(data_raw, dict) and "object" in data_raw:
            event_data = EventData.from_dict(data_raw)
        else:
            event_data = EventData(object=data_raw)

        return cls(
            id=str(d.get("id", "")),
            type=d.get("type", ""),
            created_at=d.get("created_at"),
            api_version=d.get("api_version"),
            data=event_data,
        )

    def to_dict(self) -> dict[str, Any]:
        result: dict[str, Any] = {
            "id": self.id,
            "object": "event",
            "type": self.type,
            "created_at": self.created_at,
            "data": {
                "object": self.data.object,
            },
        }
        if self.api_version:
            result["api_version"] = self.api_version
        if self.data.previous_attributes:
            result["data"]["previous_attributes"] = self.data.previous_attributes
        return result

    def __repr__(self) -> str:
        return f"<Event id={self.id} type={self.type}>"
