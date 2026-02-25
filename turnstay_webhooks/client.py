from __future__ import annotations

import asyncio
import json
import logging
from typing import Any

import httpx

from .errors import WebhookClientError

logger = logging.getLogger(__name__)


class WebhookClient:
    """Async client for emitting webhook events to the TurnStay webhook-service.

    Usage:
        client = WebhookClient(base_url="http://localhost:8000")
        await client.trigger("payment_intent.succeeded", data={...})
    """

    def __init__(
        self,
        base_url: str | None = None,
        timeout: float = 5.0,
        max_retries: int = 3,
        retry_delay: float = 1.0,
        mode: str = "http",
        queue_url: str | None = None,
        region_name: str = "eu-west-1",
    ):
        """
        Args:
            base_url: Webhook service URL (required for HTTP mode).
            timeout: HTTP request timeout in seconds.
            max_retries: Number of retries on transient failure.
            retry_delay: Base delay between retries (exponential backoff).
            mode: Transport mode - "http" or "sqs".
            queue_url: SQS queue URL (required for SQS mode).
            region_name: AWS region for SQS.
        """
        self.mode = mode
        self.base_url = base_url
        self.timeout = timeout
        self.max_retries = max_retries
        self.retry_delay = retry_delay
        self.queue_url = queue_url
        self.region_name = region_name
        self._http_client: httpx.AsyncClient | None = None

        if mode == "http" and not base_url:
            raise WebhookClientError("base_url is required for HTTP mode")
        if mode == "sqs" and not queue_url:
            raise WebhookClientError("queue_url is required for SQS mode")

    @property
    def http_client(self) -> httpx.AsyncClient:
        if self._http_client is None or self._http_client.is_closed:
            self._http_client = httpx.AsyncClient(timeout=self.timeout)
        return self._http_client

    async def trigger(
        self,
        event_type: str,
        data: dict[str, Any],
        name: str | None = None,
    ) -> dict[str, Any] | None:
        """Emit a webhook event.

        Args:
            event_type: The event type string (e.g., "payment_intent.succeeded").
            data: The event payload. Should follow the data.object pattern.
            name: Optional human-readable name for the event.

        Returns:
            Response dict from the webhook-service (HTTP mode) or None (SQS mode).

        Raises:
            WebhookClientError: If all retries are exhausted or configuration is wrong.
        """
        if name is None:
            name = event_type

        payload = {
            "event_type": event_type,
            "name": name,
            "data": data,
        }

        if self.mode == "sqs":
            return await self._send_sqs(payload)
        return await self._send_http(payload)

    async def _send_http(self, payload: dict[str, Any]) -> dict[str, Any]:
        url = f"{self.base_url}/internal/webhooks/trigger"
        last_error: Exception | None = None

        for attempt in range(self.max_retries + 1):
            try:
                response = await self.http_client.post(url, json=payload)
                if response.status_code < 500:
                    return response.json()
                last_error = WebhookClientError(
                    f"Server error {response.status_code}: {response.text}"
                )
            except httpx.TimeoutException as e:
                last_error = e
            except httpx.ConnectError as e:
                last_error = e
            except Exception as e:
                raise WebhookClientError(f"Unexpected error: {e}") from e

            if attempt < self.max_retries:
                delay = self.retry_delay * (2**attempt)
                logger.warning(
                    "Webhook trigger attempt %d/%d failed, retrying in %.1fs: %s",
                    attempt + 1,
                    self.max_retries + 1,
                    delay,
                    last_error,
                )
                await asyncio.sleep(delay)

        raise WebhookClientError(
            f"Failed to trigger webhook after {self.max_retries + 1} attempts: {last_error}"
        )

    async def _send_sqs(self, payload: dict[str, Any]) -> None:
        """Send event via SQS (for production environments)."""
        try:
            import boto3

            sqs = boto3.client("sqs", region_name=self.region_name)
            sqs.send_message(
                QueueUrl=self.queue_url,
                MessageBody=json.dumps(payload),
            )
            logger.info("Webhook event sent to SQS: %s", payload.get("event_type"))
        except ImportError:
            raise WebhookClientError(
                "boto3 is required for SQS mode. Install with: pip install boto3"
            ) from None
        except Exception as e:
            raise WebhookClientError(f"Failed to send to SQS: {e}") from e

    async def close(self) -> None:
        """Close the underlying HTTP client."""
        if self._http_client and not self._http_client.is_closed:
            await self._http_client.aclose()

    async def __aenter__(self) -> WebhookClient:
        return self

    async def __aexit__(self, *args: Any) -> None:
        await self.close()
