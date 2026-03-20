#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TINYKVM_SOURCE_DIR="${HOME}/src/tinykvm"
TINYKVM_REF="master"
BUILD_DIR="${PROJECT_ROOT}/.build/tinykvm-runner"
INSTALL_PREFIX="${HOME}/.local"

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
Usage: Install-TinyKvmTooling.sh [options]

Options:
  --tinykvm-source <path>  TinyKVM checkout path
  --tinykvm-ref <ref>      Git ref to checkout (default: master)
  --build-dir <path>       Build directory
  --install-prefix <path>  Install prefix for binaries (default: ~/.local)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tinykvm-source)
      TINYKVM_SOURCE_DIR="$2"
      shift 2
      ;;
    --tinykvm-ref)
      TINYKVM_REF="$2"
      shift 2
      ;;
    --build-dir)
      BUILD_DIR="$2"
      shift 2
      ;;
    --install-prefix)
      INSTALL_PREFIX="$2"
      shift 2
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

[[ "$(uname -s)" == "Linux" ]] || die "TinyKVM tooling requires Linux."
[[ -c /dev/kvm ]] || die "/dev/kvm is not present. TinyKVM needs KVM."
[[ -r /dev/kvm && -w /dev/kvm ]] || die "Current user cannot access /dev/kvm."

require_cmd git
require_cmd cmake
require_cmd make
require_cmd c++
require_cmd install

if [[ -d "${TINYKVM_SOURCE_DIR}/.git" ]]; then
  log "Updating TinyKVM checkout"
  git -C "${TINYKVM_SOURCE_DIR}" fetch --tags origin
else
  log "Cloning TinyKVM"
  mkdir -p "$(dirname "${TINYKVM_SOURCE_DIR}")"
  git clone https://github.com/varnish/tinykvm "${TINYKVM_SOURCE_DIR}"
fi

git -C "${TINYKVM_SOURCE_DIR}" checkout "${TINYKVM_REF}"

mkdir -p "${BUILD_DIR}"

log "Configuring TinyKVM runner"
cmake \
  -S "${PROJECT_ROOT}/tinykvm-runner" \
  -B "${BUILD_DIR}" \
  -DTINYKVM_SOURCE="${TINYKVM_SOURCE_DIR}" \
  -DCMAKE_BUILD_TYPE=Release

log "Building TinyKVM runner"
cmake --build "${BUILD_DIR}" --parallel

mkdir -p "${INSTALL_PREFIX}/bin"

log "Installing runner binaries"
install -m 0755 "${BUILD_DIR}/openclaw-tinykvm-runner" "${INSTALL_PREFIX}/bin/openclaw-tinykvm-runner"
install -m 0755 "${PROJECT_ROOT}/scripts/openclaw-tinykvm-run.sh" "${INSTALL_PREFIX}/bin/openclaw-tinykvm-run"

log "TinyKVM tooling installed"
printf 'Installed:\n'
printf '  %s\n' "${INSTALL_PREFIX}/bin/openclaw-tinykvm-runner"
printf '  %s\n' "${INSTALL_PREFIX}/bin/openclaw-tinykvm-run"
