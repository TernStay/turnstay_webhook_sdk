# SDK Development Agent Instructions

## Project Context

This project is a Python SDK that wraps an external API. Use [sdk_scaffolding](https://github.com/TernStay/sdk_scaffolding) as the starting point for new SDKs. The reference implementation is [turnstay_api_admin_sdk](https://github.com/TernStay/turnstay_api_admin_sdk).

## Core Principles

1. **Client is thin** – Methods only build kwargs, instantiate Request, call `execute(request)`
2. **Schemas hold complexity** – Params, Response, Request per endpoint
3. **client_utils.py owns HTTP** – All API call logic lives there, not in Client
4. **One test file per method** – Mirror Client structure in tests

## Key Patterns

### Client Methods
- Build kwargs (api_key, environment, params)
- Instantiate Request/GetRequest from schema
- Return `await execute(request)` – no branching, no HTTP logic

### Schema Organization
- **Params** / **GetParams** – Input (body for POST, query for GET)
- **Response** – Success shape
- **Request** / **GetRequest** – path, verb, response_type

### Adding Endpoints
1. Create schema module (Params, Response, Request)
2. Add Client method: kwargs → Request → `execute(request)`
3. Add to `run_sdk.py`. Add tests.

## Commands

```bash
pytest tests
ruff format . && ruff check .
```

## Detailed Rules

See `.cursor/rules/` for comprehensive guidelines.
