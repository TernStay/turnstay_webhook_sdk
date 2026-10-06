#!/usr/bin/env bash
# Configure AWS credentials for a GitLab CI job via OIDC.
#
# Requires:
#   - id_tokens.GITLAB_OIDC_TOKEN (aud: https://gitlab.com) on the job
#   - Role ARN argument trusted for project_path:turnstay-group/<repo>:*
#
# Usage:
#   source .gitlab/ci/scripts/aws_auth.sh
#   aws_auth_assume "$AWS_CODEARTIFACT_ROLE_ARN" "gitlab-${SERVICE_NAME}-codeartifact"
#   aws_auth_assume "$AWS_STAGING_DEPLOY_ROLE_ARN" "gitlab-${SERVICE_NAME}-staging"

set -euo pipefail

aws_auth_assume() {
  local role_arn="${1:-}"
  local session_name="${2:-gitlab-ci}"
  local region="${AWS_REGION:-${AWS_PYPI_REGION:-us-east-1}}"

  if [ -z "$role_arn" ]; then
    echo "❌ aws_auth_assume: role ARN required"
    return 1
  fi
  if [ -z "${GITLAB_OIDC_TOKEN:-}" ]; then
    echo "❌ GITLAB_OIDC_TOKEN missing — declare id_tokens on the job"
    return 1
  fi

  echo "🔐 Assuming ${role_arn} via GitLab OIDC..."
  export AWS_REGION="$region"
  export AWS_DEFAULT_REGION="$region"
  CREDS=$(aws sts assume-role-with-web-identity \
    --role-arn "$role_arn" \
    --role-session-name "$session_name" \
    --web-identity-token "$GITLAB_OIDC_TOKEN" \
    --duration-seconds 3600 \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text)
  export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | awk '{print $1}')
  export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | awk '{print $2}')
  export AWS_SESSION_TOKEN=$(echo "$CREDS" | awk '{print $3}')
  echo "✅ OIDC role assumed"
  aws sts get-caller-identity
}

mint_codeartifact_token() {
  local domain="${CODEARTIFACT_DOMAIN:-ternstay}"
  local owner="${CODEARTIFACT_DOMAIN_OWNER:-697839196252}"
  local region="${AWS_PYPI_REGION:-us-east-1}"

  echo "🔑 Minting CodeArtifact token (domain=${domain})..."
  TOKEN=$(aws codeartifact get-authorization-token \
    --domain "$domain" \
    --domain-owner "$owner" \
    --region "$region" \
    --query authorizationToken --output text)
  if [ -z "$TOKEN" ] || [ "$TOKEN" = "None" ]; then
    echo "❌ Failed to mint CodeArtifact token"
    return 1
  fi
  export CODEARTIFACT_AUTH_TOKEN="$TOKEN"
  echo "✅ CODEARTIFACT_AUTH_TOKEN exported"
}
