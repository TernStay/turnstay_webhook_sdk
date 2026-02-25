import asyncio

from turnstay_webhooks import WebhookClient

WEBHOOK_SERVICE_URL = "http://localhost:8000"


async def run_trigger_example():
    client = WebhookClient(base_url=WEBHOOK_SERVICE_URL)
    try:
        response = await client.trigger(
            event_type="payment_intent.succeeded",
            data={
                "object": {
                    "id": "pi_example_123",
                    "amount": 5000,
                    "currency": "usd",
                    "status": "succeeded",
                }
            },
        )
        print("---------------------------------------------------------------")
        print("Trigger Response:", response)
        print("---------------------------------------------------------------")
        return response
    except Exception as e:
        print("---------------------------------------------------------------")
        print(f"Trigger failed: {e}")
        print("---------------------------------------------------------------")
    finally:
        await client.close()


async def main():
    print("---------------------------------------------------------------")
    print("TurnStay Webhooks SDK - Example")
    print("---------------------------------------------------------------")
    await run_trigger_example()
    print("---------------------------------------------------------------")
    print("Done.")
    print("---------------------------------------------------------------")


if __name__ == "__main__":
    asyncio.run(main())
