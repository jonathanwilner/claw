#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MODEL="glm-4.7-flash"
OLLAMA_BASE_URL="http://127.0.0.1:11434"
OLLAMA_API_KEY="ollama-local"
GATEWAY_PORT="18789"
WORKSPACE_DIR="${HOME}/.openclaw/workspace"
INSTALL_OPENCLAW=1
START_OLLAMA=1
APPLY_SYSTEMD_HARDENING=1
COMPOSE_OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-${PROJECT_ROOT}/state/openclaw-config}"
COMPOSE_OPENCLAW_WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-${PROJECT_ROOT}/state/openclaw-workspace}"
COMPOSE_OLLAMA_DATA_DIR="${OLLAMA_DATA_DIR:-${PROJECT_ROOT}/state/ollama}"

log() {
  printf '==> %s\n' "$1"
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

ollama_api_reachable() {
  python3 - "${1}/api/tags" <<'PY'
import sys
import urllib.request

url = sys.argv[1]
try:
    with urllib.request.urlopen(url, timeout=5) as response:
        if 200 <= response.status < 300:
            sys.exit(0)
except Exception:
    pass
sys.exit(1)
PY
}

ollama_model_present() {
  python3 - "${1}/api/tags" "${2}" <<'PY'
import json
import sys
import urllib.request

url = sys.argv[1]
model = sys.argv[2]

with urllib.request.urlopen(url, timeout=10) as response:
    payload = json.load(response)

models = payload.get("models") or []
for entry in models:
    if entry.get("name") == model:
        sys.exit(0)

sys.exit(1)
PY
}

usage() {
  cat <<'EOF'
Usage: Install-OpenClawTinyKvmHost.sh [options]

Options:
  --model <id>             Ollama model to configure (default: glm-4.7-flash)
  --ollama-base-url <url>  Ollama base URL (default: http://127.0.0.1:11434)
  --ollama-api-key <key>   OpenClaw Ollama API key placeholder (default: ollama-local)
  --gateway-port <port>    Gateway port (default: 18789)
  --workspace-dir <path>   OpenClaw workspace directory
  --skip-openclaw-install  Assume openclaw is already installed
  --skip-ollama            Do not manage the local Ollama container
  --skip-systemd-hardening Do not apply the OpenClaw user-service hardening override
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)
      MODEL="$2"
      shift 2
      ;;
    --ollama-base-url)
      OLLAMA_BASE_URL="$2"
      shift 2
      ;;
    --ollama-api-key)
      OLLAMA_API_KEY="$2"
      shift 2
      ;;
    --gateway-port)
      GATEWAY_PORT="$2"
      shift 2
      ;;
    --workspace-dir)
      WORKSPACE_DIR="$2"
      shift 2
      ;;
    --skip-openclaw-install)
      INSTALL_OPENCLAW=0
      shift
      ;;
    --skip-ollama)
      START_OLLAMA=0
      shift
      ;;
    --skip-systemd-hardening)
      APPLY_SYSTEMD_HARDENING=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

[[ "$(uname -s)" == "Linux" ]] || die "The TinyKVM host path requires Linux."

require_cmd curl
require_cmd python3

if [[ "${START_OLLAMA}" -eq 1 ]] && ollama_api_reachable "${OLLAMA_BASE_URL}"; then
  log "Reusing existing Ollama at ${OLLAMA_BASE_URL}"
  START_OLLAMA=0
fi

if [[ "${START_OLLAMA}" -eq 1 ]]; then
  require_cmd docker
fi

if [[ "${INSTALL_OPENCLAW}" -eq 1 ]] && ! command -v openclaw >/dev/null 2>&1; then
  log "Installing OpenClaw via the official installer"
  tmp_install_script="$(mktemp)"
  trap 'rm -f "${tmp_install_script}"' EXIT
  curl -fsSL https://openclaw.ai/install.sh -o "${tmp_install_script}"
  bash "${tmp_install_script}" --no-onboard
  hash -r
fi

require_cmd openclaw

mkdir -p "${WORKSPACE_DIR}"
mkdir -p "${COMPOSE_OPENCLAW_CONFIG_DIR}" "${COMPOSE_OPENCLAW_WORKSPACE_DIR}" "${COMPOSE_OLLAMA_DATA_DIR}"

if [[ "${START_OLLAMA}" -eq 1 ]]; then
  log "Starting Ollama container"
  env \
    OLLAMA_DATA_DIR="${COMPOSE_OLLAMA_DATA_DIR}" \
    OPENCLAW_CONFIG_DIR="${COMPOSE_OPENCLAW_CONFIG_DIR}" \
    OPENCLAW_WORKSPACE_DIR="${COMPOSE_OPENCLAW_WORKSPACE_DIR}" \
    docker compose --project-directory "${PROJECT_ROOT}" -f "${PROJECT_ROOT}/compose.yaml" up -d ollama

  log "Waiting for Ollama"
  python3 - "${OLLAMA_BASE_URL}/api/tags" <<'PY'
import sys
import time
import urllib.request

url = sys.argv[1]
deadline = time.time() + 300
while time.time() < deadline:
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            if 200 <= response.status < 500:
                sys.exit(0)
    except Exception:
        time.sleep(2)
        continue
    time.sleep(2)

print(f"Timed out waiting for {url}", file=sys.stderr)
sys.exit(1)
PY

  log "Ensuring Ollama model ${MODEL} is present"
  if ! env \
    OLLAMA_DATA_DIR="${COMPOSE_OLLAMA_DATA_DIR}" \
    OPENCLAW_CONFIG_DIR="${COMPOSE_OPENCLAW_CONFIG_DIR}" \
    OPENCLAW_WORKSPACE_DIR="${COMPOSE_OPENCLAW_WORKSPACE_DIR}" \
    docker compose --project-directory "${PROJECT_ROOT}" -f "${PROJECT_ROOT}/compose.yaml" exec -T ollama ollama list | grep -Fq "${MODEL}"; then
    env \
      OLLAMA_DATA_DIR="${COMPOSE_OLLAMA_DATA_DIR}" \
      OPENCLAW_CONFIG_DIR="${COMPOSE_OPENCLAW_CONFIG_DIR}" \
      OPENCLAW_WORKSPACE_DIR="${COMPOSE_OPENCLAW_WORKSPACE_DIR}" \
      docker compose --project-directory "${PROJECT_ROOT}" -f "${PROJECT_ROOT}/compose.yaml" exec -T ollama ollama pull "${MODEL}"
  fi
fi

if [[ "${START_OLLAMA}" -eq 0 ]] && ollama_api_reachable "${OLLAMA_BASE_URL}" && ! ollama_model_present "${OLLAMA_BASE_URL}" "${MODEL}"; then
  if command -v ollama >/dev/null 2>&1; then
    log "Pulling ${MODEL} into the existing Ollama instance"
    if ! OLLAMA_HOST="${OLLAMA_BASE_URL}" ollama pull "${MODEL}"; then
      die "Failed to pull ${MODEL} from the existing Ollama instance at ${OLLAMA_BASE_URL}. Upgrade Ollama or rerun with --model <compatible-model>."
    fi
  else
    die "Existing Ollama is reachable at ${OLLAMA_BASE_URL}, but the ollama CLI is unavailable and ${MODEL} is missing. Install the ollama CLI or rerun with --model <available-model> after preparing the server."
  fi
fi

log "Configuring OpenClaw for a TinyKVM-friendly host layout"
openclaw config set gateway.mode local
openclaw config set gateway.bind loopback
openclaw config set gateway.port "${GATEWAY_PORT}"
openclaw config set gateway.auth.mode token
openclaw config set gateway.auth.token "$(python3 -c 'import secrets; print(secrets.token_hex(24))')"
openclaw config set agents.defaults.workspace "${WORKSPACE_DIR}"
openclaw config set agents.defaults.model.primary "ollama/${MODEL}"
openclaw config set agents.defaults.sandbox.mode off
openclaw config set models.providers.ollama.apiKey "${OLLAMA_API_KEY}"
openclaw config set models.providers.ollama.baseUrl "${OLLAMA_BASE_URL}"
openclaw config set models.providers.ollama.api ollama

log "Running OpenClaw health checks"
openclaw doctor --non-interactive || true

log "Installing and starting the OpenClaw gateway service"
openclaw gateway install || true
openclaw gateway restart || openclaw gateway start

if [[ "${APPLY_SYSTEMD_HARDENING}" -eq 1 ]]; then
  log "Applying Linux user-service hardening for the OpenClaw gateway"
  "${PROJECT_ROOT}/scripts/Apply-OpenClawSystemdHardening.sh"
fi

log "OpenClaw TinyKVM host setup complete"
printf 'Suggested next steps:\n'
printf '  %s\n' "openclaw gateway status --deep"
printf '  %s\n' "openclaw models list"
printf '  %s\n' "${PROJECT_ROOT}/scripts/Validate-OpenClawTinyKvmHost.sh"
printf '  %s\n' "openclaw-tinykvm-run /path/to/linux-elf"
