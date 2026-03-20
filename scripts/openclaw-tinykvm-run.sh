#!/usr/bin/env bash
set -euo pipefail

RUNNER_BIN="${OPENCLAW_TINYKVM_RUNNER_BIN:-openclaw-tinykvm-runner}"
TIMEOUT_SECONDS="${OPENCLAW_TINYKVM_TIMEOUT_SECONDS:-15}"
MAX_MEM_MIB="${OPENCLAW_TINYKVM_MAX_MEM_MIB:-1024}"
MAX_COW_MIB="${OPENCLAW_TINYKVM_MAX_COW_MIB:-256}"
if [[ -n "${OPENCLAW_TINYKVM_DYNAMIC_LOADER:-}" ]]; then
  DYNAMIC_LOADER_ARGS=(--dynamic-loader "${OPENCLAW_TINYKVM_DYNAMIC_LOADER}")
else
  DYNAMIC_LOADER_ARGS=()
fi

READ_PREFIX_ARGS=()
if [[ -n "${OPENCLAW_TINYKVM_EXTRA_READ_PREFIXES:-}" ]]; then
  IFS=':' read -r -a extra_prefixes <<< "${OPENCLAW_TINYKVM_EXTRA_READ_PREFIXES}"
  for prefix in "${extra_prefixes[@]}"; do
    [[ -n "${prefix}" ]] || continue
    READ_PREFIX_ARGS+=(--read-prefix "${prefix}")
  done
fi

exec "${RUNNER_BIN}" \
  --timeout-seconds "${TIMEOUT_SECONDS}" \
  --max-mem-mib "${MAX_MEM_MIB}" \
  --max-cow-mib "${MAX_COW_MIB}" \
  "${DYNAMIC_LOADER_ARGS[@]}" \
  "${READ_PREFIX_ARGS[@]}" \
  -- "$@"
