#!/usr/bin/env bash
# Install Poetry deps. Prefer Poetry `dev` group; else PEP 621 optional-dependencies
# (e.g. hatchling SDKs with [project.optional-dependencies] test/dev).
set -euo pipefail

if grep -qE '\[tool\.poetry\.group\.dev(\.|])' pyproject.toml 2>/dev/null \
  || grep -qE '^\[dev-dependencies\]' pyproject.toml 2>/dev/null; then
  echo "📦 poetry install --with dev"
  poetry install --no-interaction --with dev "$@"
elif grep -qE '\[project\.optional-dependencies\]' pyproject.toml 2>/dev/null; then
  extras=()
  if awk '
    /^\[project\.optional-dependencies\]/ { in_opt=1; next }
    /^\[/ { in_opt=0 }
    in_opt && /^test[[:space:]]*=/ { found=1 }
    END { exit !found }
  ' pyproject.toml; then
    extras+=(test)
  fi
  if awk '
    /^\[project\.optional-dependencies\]/ { in_opt=1; next }
    /^\[/ { in_opt=0 }
    in_opt && /^dev[[:space:]]*=/ { found=1 }
    END { exit !found }
  ' pyproject.toml; then
    extras+=(dev)
  fi
  if [ "${#extras[@]}" -gt 0 ]; then
    # poetry: --extras test --extras dev
    args=()
    for e in "${extras[@]}"; do
      args+=(--extras "$e")
    done
    echo "📦 poetry install ${args[*]}"
    poetry install --no-interaction "${args[@]}" "$@"
  else
    echo "📦 poetry install (optional-dependencies present, no test/dev extras matched)"
    poetry install --no-interaction "$@"
  fi
else
  echo "📦 poetry install (no dev group)"
  poetry install --no-interaction "$@"
fi
