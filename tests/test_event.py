import hashlib
import hmac
import json
import time

from turnstay_webhooks.event import Event, EventData


def _make_signed_payload(secret: str, payload_dict: dict) -> tuple[str, str]:
    payload_str = json.dumps(payload_dict)
    ts = str(int(time.time()))
    to_sign = f"{ts}.{payload_str}"
    sig = hmac.new(
        secret.encode("utf-8"),
        to_sign.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    header = f"t={ts}, v1={sig}"
    return payload_str, header


class TestEventData:
    def test_from_dict_with_object(self):
        raw = {"object": {"id": "pi_1", "amount": 100}, "previous_attributes": {"amount": 50}}
        data = EventData.from_dict(raw)
        assert data.object["id"] == "pi_1"
        assert data.previous_attributes["amount"] == 50

    def test_from_dict_without_previous(self):
        raw = {"object": {"id": "pi_2"}}
        data = EventData.from_dict(raw)
        assert data.object["id"] == "pi_2"
        assert data.previous_attributes is None


class TestEvent:
    SECRET = "whsec_test_event"

    def test_construct_from(self):
        payload_dict = {
            "id": "evt_123",
            "type": "payment_intent.succeeded",
            "api_version": "2026-01-01",
            "created_at": "2026-02-25T12:00:00",
            "data": {
                "object": {"id": "pi_1", "amount": 5000, "status": "succeeded"},
            },
        }
        payload_str, header = _make_signed_payload(self.SECRET, payload_dict)
        event = Event.construct_from(payload_str, header, self.SECRET)

        assert event.id == "evt_123"
        assert event.type == "payment_intent.succeeded"
        assert event.data.object["id"] == "pi_1"
        assert event.data.object["amount"] == 5000
        assert event.api_version == "2026-01-01"

    def test_from_dict(self):
        d = {
            "id": "evt_456",
            "type": "refund.completed",
            "data": {"object": {"id": "rfnd_1", "status": "completed"}},
        }
        event = Event.from_dict(d)
        assert event.type == "refund.completed"
        assert event.data.object["status"] == "completed"

    def test_to_dict_roundtrip(self):
        original = {
            "id": "evt_789",
            "type": "chargeback.created",
            "api_version": "2026-01-01",
            "created_at": "2026-02-25T12:00:00",
            "data": {
                "object": {"id": "cb_1"},
                "previous_attributes": {"status": "pending"},
            },
        }
        event = Event.from_dict(original)
        result = event.to_dict()
        assert result["type"] == "chargeback.created"
        assert result["data"]["object"]["id"] == "cb_1"
        assert result["data"]["previous_attributes"]["status"] == "pending"

    def test_event_repr(self):
        event = Event.from_dict({"id": "evt_1", "type": "payout.completed", "data": {"object": {}}})
        assert "evt_1" in repr(event)
        assert "payout.completed" in repr(event)
