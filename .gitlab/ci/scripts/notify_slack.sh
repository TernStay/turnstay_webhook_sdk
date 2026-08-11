#!/usr/bin/env bash
# Post a Slack #deployments notification matching the GitHub notify-slack action format.
#
# Required env:
#   KIND                  deploy-ecs | sdk-publish
#   SLACK_BOT_USER_OAUTH_ACCESS_TOKEN
#   SLACK_CHANNEL_ID
#   NAME                  service or package display name
#
# Optional env:
#   ENVIRONMENT           staging | production (deploy-ecs)
#   ENABLE_AWS_DEPLOY     true|false (deploy-ecs success gating)
#   PACKAGE / VERSION / PREVIOUS_VERSION / PUBLISHED  (sdk-publish)
#   TRIGGER               default: merge to main
#   SERVICE_URL / CLOUDWATCH_URL / ECS_URL
#   REGISTRY_URL          default for SDK: AWS CodeArtifact (ternstay00)
#
# Uses GitLab CI predefined variables and CI_JOB_TOKEN to inspect sibling jobs.
set -euo pipefail

export KIND="${KIND:-deploy-ecs}"
export TRIGGER="${TRIGGER:-merge to main}"
export ENVIRONMENT="${ENVIRONMENT:-staging}"
export ENABLE_AWS_DEPLOY="${ENABLE_AWS_DEPLOY:-false}"
export REGISTRY_URL="${REGISTRY_URL:-AWS CodeArtifact (ternstay00)}"
export NAME="${NAME:-${SERVICE_DISPLAY_NAME:-${PACKAGE_DISPLAY_NAME:-unknown}}}"
export PACKAGE="${PACKAGE:-${PACKAGE_DISPLAY_NAME:-$NAME}}"
export VERSION="${VERSION:-}"
export PREVIOUS_VERSION="${PREVIOUS_VERSION:-}"
export PUBLISHED="${PUBLISHED:-}"
export SERVICE_URL="${SERVICE_URL:-}"
export CLOUDWATCH_URL="${CLOUDWATCH_URL:-}"
export ECS_URL="${ECS_URL:-}"

if [ -z "${SLACK_BOT_USER_OAUTH_ACCESS_TOKEN:-}" ] || [ -z "${SLACK_CHANNEL_ID:-}" ]; then
  echo "Slack credentials missing — skipping notify"
  exit 0
fi
if [ "${ENABLE_SLACK_NOTIFY:-true}" != "true" ]; then
  echo "ENABLE_SLACK_NOTIFY=false — skipping"
  exit 0
fi

export SHORT_SHA="${CI_COMMIT_SHORT_SHA:-${CI_COMMIT_SHA:0:7}}"
export COMMIT_URL="${CI_PROJECT_URL}/-/commit/${CI_COMMIT_SHA}"
export RUN_URL="${CI_PIPELINE_URL}"
export BRANCH_NAME="${CI_COMMIT_BRANCH:-${CI_COMMIT_REF_NAME:-main}}"
export ACTOR="${GITLAB_USER_LOGIN:-unknown}"

JOBS_JSON="[]"
if [ -n "${CI_JOB_TOKEN:-}" ] && [ -n "${CI_API_V4_URL:-}" ]; then
  JOBS_JSON=$(curl -sS --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
    "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/pipelines/${CI_PIPELINE_ID}/jobs?per_page=100" \
    || echo '[]')
fi
export JOBS_JSON

python3 - <<'PY'
import json
import os
import urllib.request

kind = os.environ["KIND"]
enable_deploy = os.environ.get("ENABLE_AWS_DEPLOY", "false") == "true"
published = os.environ.get("PUBLISHED", "")
jobs = json.loads(os.environ.get("JOBS_JSON") or "[]")

ignore = {"notify-slack", "notify-slack-production"}
failed = []
by_name = {}
for j in jobs:
    name = j.get("name") or ""
    if name in ignore:
        continue
    by_name[name] = j.get("status")
    if j.get("status") == "failed" and not j.get("allow_failure"):
        failed.append(name)

status = "failure" if failed else "success"
send = False


def job_status(*names):
    for n in names:
        if n in by_name:
            return by_name[n]
    for n, st in by_name.items():
        for want in names:
            if n == want or n.startswith(want + " ") or n.startswith(want + ":"):
                return st
    return None


if kind == "sdk-publish":
    if failed:
        send = True
    elif published == "true":
        send = True
elif kind == "deploy-ecs":
    if failed:
        send = True
    elif enable_deploy and status == "success":
        deploy = job_status("deploy-staging", "deploy-production")
        if deploy == "success":
            send = True

if not send:
    print(
        f"Skipping Slack notify (send=false, status={status}, published={published or '-'})"
    )
    raise SystemExit(0)

name = os.environ["NAME"]
package = os.environ["PACKAGE"]
version = os.environ.get("VERSION") or ""
prev = os.environ.get("PREVIOUS_VERSION") or ""
trigger = os.environ["TRIGGER"]
actor = os.environ["ACTOR"]
short = os.environ["SHORT_SHA"]
commit_url = os.environ["COMMIT_URL"]
run_url = os.environ["RUN_URL"]
branch = os.environ["BRANCH_NAME"]
failed_jobs = ", ".join(failed)
service_url = os.environ.get("SERVICE_URL") or ""
cw = os.environ.get("CLOUDWATCH_URL") or ""
ecs = os.environ.get("ECS_URL") or ""
registry = os.environ.get("REGISTRY_URL") or ""
environment = os.environ["ENVIRONMENT"]
env_label = environment[:1].upper() + environment[1:]


def lines(*parts):
    return "\n".join(parts)


if kind == "sdk-publish":
    if status == "success":
        ver_line = version
        if prev and prev != version:
            ver_line = f"{prev} → {version}"
        msg = lines(
            "📦 *SDK Published*",
            "",
            f"*Package:* {package or name}",
            f"*Version:* {ver_line}",
            f"*Registry:* {registry}",
            f"*Trigger:* {trigger}",
            f"*Actor:* {actor}",
            f"*Commit:* <{commit_url}|{short}>",
            f"*Run:* <{run_url}|View workflow>",
            "",
            f"*Install:* `poetry add {package or name}@{version}` (via CodeArtifact)",
        )
        emoji = ":package:"
    else:
        msg = lines(
            "❌ *SDK Publish Failed*",
            "",
            f"*Package:* {package or name}",
            f"*Attempted version:* {version or 'unknown'}",
            f"*Trigger:* {trigger}",
            f"*Actor:* {actor}",
            f"*Commit:* <{commit_url}|{short}>",
            f"*Run:* <{run_url}|View workflow>",
        )
        if failed_jobs:
            msg += f"\n*Failed job(s):* {failed_jobs}"
        emoji = ":x:"
else:
    if status == "success":
        if environment == "production":
            header = "🎉 *Production Deployment Successful*"
            footer = "🚀 *Status:* Live in production!"
            emoji = ":tada:"
        else:
            header = "🚀 *Deployment Successful*"
            footer = "✅ *Status:* All checks passed!"
            emoji = ":rocket:"
        msg = lines(
            header,
            "",
            f"*Service:* {name}",
            f"*Environment:* {env_label}",
            f"*Branch:* {branch}",
            f"*Trigger:* {trigger}",
            f"*Actor:* {actor}",
            f"*Commit:* <{commit_url}|{short}>",
            f"*Run:* <{run_url}|View workflow>",
        )
        if service_url:
            msg += f"\n*Service URL:* {service_url}"
        if cw:
            msg += f"\n*CloudWatch:* {cw}"
        if ecs:
            msg += f"\n*ECS:* {ecs}"
        msg += f"\n\n{footer}"
    else:
        if environment == "production":
            header = "🚨 *PRODUCTION DEPLOYMENT FAILED*"
            footer = "🚨 *Status:* CRITICAL — production deployment failed!"
            emoji = ":rotating_light:"
        else:
            header = "❌ *Deployment Failed*"
            footer = "⚠️ *Status:* Deployment failed — immediate attention needed!"
            emoji = ":x:"
        msg = lines(
            header,
            "",
            f"*Service:* {name}",
            f"*Environment:* {env_label}",
            f"*Branch:* {branch}",
            f"*Trigger:* {trigger}",
            f"*Actor:* {actor}",
            f"*Commit:* <{commit_url}|{short}>",
            f"*Run:* <{run_url}|View workflow>",
        )
        if failed_jobs:
            msg += f"\n*Failed job(s):* {failed_jobs}"
        if service_url:
            msg += f"\n*Service URL:* {service_url}"
        if cw:
            msg += f"\n*CloudWatch:* {cw}"
        if ecs:
            msg += f"\n*ECS:* {ecs}"
        msg += f"\n\n{footer}"

payload = {
    "channel": os.environ["SLACK_CHANNEL_ID"],
    "text": msg,
    "icon_emoji": emoji,
}
req = urllib.request.Request(
    "https://slack.com/api/chat.postMessage",
    data=json.dumps(payload).encode(),
    headers={
        "Authorization": "Bearer " + os.environ["SLACK_BOT_USER_OAUTH_ACCESS_TOKEN"],
        "Content-Type": "application/json; charset=utf-8",
    },
    method="POST",
)
with urllib.request.urlopen(req) as resp:
    body = json.loads(resp.read().decode())
if not body.get("ok"):
    raise SystemExit(f"Slack API error: {body}")
print("Slack notify sent OK")
PY
