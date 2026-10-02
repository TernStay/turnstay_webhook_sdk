#!/usr/bin/env bash
# Build and publish Poetry package to CodeArtifact (idempotent).
set -euo pipefail

DOMAIN="${CODEARTIFACT_DOMAIN:-ternstay}"
OWNER="${CODEARTIFACT_DOMAIN_OWNER:-697839196252}"
REPO="${CODEARTIFACT_REPOSITORY:-ternstay00}"
REGION="${AWS_PYPI_REGION:-us-east-1}"

echo "🔨 Building package..."
poetry build

python -m pip install -q --upgrade twine

echo "🔐 Configuring CodeArtifact twine login..."
aws codeartifact login --tool twine \
  --domain "$DOMAIN" \
  --domain-owner "$OWNER" \
  --repository "$REPO" \
  --region "$REGION"

VERSION=$(poetry version -s)
PACKAGE=$(poetry run python -c "import tomllib; print(tomllib.load(open('pyproject.toml','rb'))['tool']['poetry']['name'])")
echo "Package: ${PACKAGE}@${VERSION}"

PREVIOUS=$(aws codeartifact list-package-versions \
  --domain "$DOMAIN" --domain-owner "$OWNER" --repository "$REPO" \
  --format pypi --package "$PACKAGE" --region "$REGION" \
  --sort-by PUBLISH_TIME --max-results 1 \
  --query 'versions[0].version' --output text 2>/dev/null || true)
if [ "$PREVIOUS" = "None" ]; then PREVIOUS=""; fi

EXISTING=$(aws codeartifact list-package-versions \
  --domain "$DOMAIN" --domain-owner "$OWNER" --repository "$REPO" \
  --format pypi --package "$PACKAGE" --region "$REGION" \
  --query "versions[?version=='${VERSION}'].version" \
  --output text 2>/dev/null || true)

{
  echo "SDK_PACKAGE=${PACKAGE}"
  echo "SDK_VERSION=${VERSION}"
  echo "SDK_PREVIOUS_VERSION=${PREVIOUS}"
} > sdk-publish.env

if [ -n "$EXISTING" ] && [ "$EXISTING" != "None" ]; then
  echo "✅ ${PACKAGE}@${VERSION} already published — skipping upload"
  echo "SDK_PUBLISHED=skipped" >> sdk-publish.env
  exit 0
fi

echo "🚀 Publishing ${PACKAGE}@${VERSION}..."
set +e
UPLOAD_OUT=$(python -m twine upload --repository codeartifact dist/* 2>&1)
UPLOAD_RC=$?
set -e
echo "$UPLOAD_OUT"
if [ $UPLOAD_RC -eq 0 ]; then
  echo "SDK_PUBLISHED=true" >> sdk-publish.env
elif echo "$UPLOAD_OUT" | grep -qiE '409|Conflict|already exists'; then
  echo "✅ Version already published (409) — treating as success"
  echo "SDK_PUBLISHED=skipped" >> sdk-publish.env
  exit 0
else
  echo "SDK_PUBLISHED=false" >> sdk-publish.env
  exit $UPLOAD_RC
fi
