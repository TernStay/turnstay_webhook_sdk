#!/usr/bin/env bash
# Install Poetry deps. Use the `dev` group when declared; otherwise plain install.
set -euo pipefail

if grep -qE '\[tool\.poetry\.group\.dev(\.|])' pyproject.toml 2>/dev/null \
  || grep -qE '^\[dev-dependencies\]' pyproject.toml 2>/dev/null; then
  echo "📦 poetry install --with dev"
  poetry install --no-interaction --with dev "$@"
else
  echo "📦 poetry install (no dev group)"
  poetry install --no-interaction "$@"
fi
