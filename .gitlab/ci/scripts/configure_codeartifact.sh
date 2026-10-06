#!/usr/bin/env bash
# Authenticate Poetry to the existing CodeArtifact source in pyproject.toml.
# Do NOT add/remove/reorder sources here — that mutates pyproject.toml and
# invalidates poetry.lock's content-hash.
set -euo pipefail

if [ -z "${CODEARTIFACT_AUTH_TOKEN:-}" ]; then
  if declare -F mint_codeartifact_token >/dev/null 2>&1; then
    mint_codeartifact_token
  else
    echo "❌ CODEARTIFACT_AUTH_TOKEN not set"
    exit 1
  fi
fi

echo "🔐 Configuring Poetry CodeArtifact credentials (source left unchanged)"
poetry config http-basic.codeartifact aws "$CODEARTIFACT_AUTH_TOKEN"
echo "✅ Poetry CodeArtifact auth ready"
