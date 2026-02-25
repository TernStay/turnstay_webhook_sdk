# turnstay_webhooks

Python SDK for TurnStay webhook-service — emit events, verify signatures, and consume webhook payloads.

## Prerequisites

* Python >= 3.10

## Virtual Environment

```bash
pyenv virtualenv 3.11.2 turnstay-webhooks
pyenv activate turnstay-webhooks
pyenv local turnstay-webhooks
```

## Install

```bash
pip install -r requirements.txt
```

For SQS transport mode:

```bash
pip install -r requirements.txt boto3
```

## Usage

### Emitting events (producer side)

```python
import asyncio
from turnstay_webhooks import WebhookClient

async def main():
    client = WebhookClient(base_url="http://localhost:8000")
    await client.trigger(
        event_type="payment_intent.succeeded",
        data={
            "object": {
                "id": "pi_123",
                "amount": 5000,
                "currency": "usd",
                "status": "succeeded",
            }
        },
    )

asyncio.run(main())
```

### Consuming webhooks (subscriber side)

```python
from turnstay_webhooks import Event

event = Event.construct_from(
    payload=request.body,
    signature=request.headers["Turnstay-Signature"],
    secret="whsec_your_endpoint_secret",
)

match event.type:
    case "payment_intent.succeeded":
        pi = event.data.object
        print(f"Payment {pi['id']} succeeded for {pi['amount']}")
    case "refund.completed":
        refund = event.data.object
        print(f"Refund {refund['id']} completed")
    case _:
        print(f"Unhandled event type: {event.type}")
```

### Verifying signatures manually

```python
from turnstay_webhooks import WebhookSignature

parsed = WebhookSignature.verify(
    payload=raw_body,
    signature_header=sig_header,
    secret="whsec_...",
)
```

## Testing

### Install dev dependencies

```bash
pip install -r development.txt
```

### Run tests

```bash
pytest tests
```

## Deployment

This project uses hatch to build and publish the package.

```bash
hatch build
hatch publish
```
