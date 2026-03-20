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

if [[ "${START_OLLAMA}" -eq 1 ]]; then
  log "Starting Ollama container"
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
  if ! docker compose --project-directory "${PROJECT_ROOT}" -f "${PROJECT_ROOT}/compose.yaml" exec -T ollama ollama list | grep -Fq "${MODEL}"; then
    docker compose --project-directory "${PROJECT_ROOT}" -f "${PROJECT_ROOT}/compose.yaml" exec -T ollama ollama pull "${MODEL}"
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
