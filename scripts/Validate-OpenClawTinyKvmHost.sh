#!/usr/bin/env bash
set -euo pipefail

OLLAMA_TAGS_URL="http://127.0.0.1:11434/api/tags"
USER_SYSTEMD_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/systemd/user"
UNIT_NAME="${OPENCLAW_SYSTEMD_UNIT:-}"
PROFILE="${OPENCLAW_PROFILE:-}"

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

normalize_unit_name() {
  local raw="$1"
  raw="${raw%.service}"
  printf '%s' "${raw}"
}

resolve_default_unit_name() {
  local profile_name="${1:-}"
  if [[ -n "${profile_name}" && "${profile_name}" != "default" ]]; then
    printf 'openclaw-gateway-%s' "${profile_name}"
  else
    printf 'openclaw-gateway'
  fi
}

resolve_existing_unit_name() {
  local candidate
  local candidates=()

  if [[ -n "${UNIT_NAME}" ]]; then
    candidates+=("$(normalize_unit_name "${UNIT_NAME}")")
  fi

  if [[ -n "${PROFILE}" ]]; then
    candidates+=("$(resolve_default_unit_name "${PROFILE}")")
  fi

  candidates+=("$(resolve_default_unit_name "")")
  candidates+=("clawdbot-gateway")
  candidates+=("moltbot-gateway")

  for candidate in "${candidates[@]}"; do
    if [[ -f "${USER_SYSTEMD_DIR}/${candidate}.service" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done

  mapfile -t candidates < <(find "${USER_SYSTEMD_DIR}" -maxdepth 1 -type f \( -name 'openclaw-gateway*.service' -o -name 'clawdbot-gateway.service' -o -name 'moltbot-gateway.service' \) -printf '%f\n' 2>/dev/null | sed 's/\.service$//' | sort -u)

  if [[ "${#candidates[@]}" -eq 1 ]]; then
    printf '%s' "${candidates[0]}"
    return 0
  fi

  if [[ "${#candidates[@]}" -gt 1 ]]; then
    die "Multiple OpenClaw systemd units were found in ${USER_SYSTEMD_DIR}; set OPENCLAW_SYSTEMD_UNIT or OPENCLAW_PROFILE"
  fi

  die "No OpenClaw systemd user unit was found in ${USER_SYSTEMD_DIR}"
}

require_config_value() {
  local key="$1"
  local expected="$2"
  local actual

  actual="$(openclaw config get "${key}")"
  [[ "${actual}" == "${expected}" ]] || die "Expected ${key}=${expected}, got ${actual}"
}

require_cmd openclaw
require_cmd curl
require_cmd rg

log "Checking KVM access"
[[ -c /dev/kvm ]] || die "/dev/kvm is missing"
[[ -r /dev/kvm && -w /dev/kvm ]] || die "Current user cannot access /dev/kvm"

log "Checking TinyKVM runner"
require_cmd openclaw-tinykvm-runner
require_cmd openclaw-tinykvm-run

log "Checking Ollama API"
curl -fsS "${OLLAMA_TAGS_URL}" >/dev/null

log "Checking OpenClaw gateway"
require_config_value gateway.mode local
require_config_value gateway.bind loopback
require_config_value gateway.auth.mode token
require_config_value agents.defaults.sandbox.mode off
openclaw gateway status --deep
openclaw health
openclaw models list

log "Checking OpenClaw systemd hardening override"
UNIT_NAME="$(resolve_existing_unit_name)"
OVERRIDE_PATH="${USER_SYSTEMD_DIR}/${UNIT_NAME}.service.d/override.conf"
[[ -f "${OVERRIDE_PATH}" ]] || die "Missing systemd hardening override: ${OVERRIDE_PATH}"
rg -q '^NoNewPrivileges=yes$' "${OVERRIDE_PATH}" || die "NoNewPrivileges is missing from ${OVERRIDE_PATH}"
rg -q '^PrivateTmp=yes$' "${OVERRIDE_PATH}" || die "PrivateTmp is missing from ${OVERRIDE_PATH}"
rg -q '^ProtectKernelModules=yes$' "${OVERRIDE_PATH}" || die "ProtectKernelModules is missing from ${OVERRIDE_PATH}"
rg -q '^ProtectSystem=full$' "${OVERRIDE_PATH}" || die "ProtectSystem=full is missing from ${OVERRIDE_PATH}"

log "Validation passed"
