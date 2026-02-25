import pytest

from turnstay_webhooks.client import WebhookClient
from turnstay_webhooks.errors import WebhookClientError


class TestWebhookClientInit:
    def test_http_mode_requires_base_url(self):
        with pytest.raises(WebhookClientError, match="base_url"):
            WebhookClient(mode="http")

    def test_sqs_mode_requires_queue_url(self):
        with pytest.raises(WebhookClientError, match="queue_url"):
            WebhookClient(mode="sqs")

    def test_http_mode_valid(self):
        client = WebhookClient(base_url="http://localhost:8000")
        assert client.mode == "http"
        assert client.base_url == "http://localhost:8000"

    def test_sqs_mode_valid(self):
        client = WebhookClient(mode="sqs", queue_url="https://sqs.eu-west-1.amazonaws.com/123/queue")
        assert client.mode == "sqs"
        assert client.queue_url is not None

    def test_default_settings(self):
        client = WebhookClient(base_url="http://localhost:8000")
        assert client.timeout == 5.0
        assert client.max_retries == 3
        assert client.retry_delay == 1.0
