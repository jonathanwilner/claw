# TinyKVM Guide

[简体中文](tinykvm.zh-CN.md)

## What Changed

This repository now includes a Linux-first path for running OpenClaw next to TinyKVM.

That path is intentionally different from the older Windows / WSL2 / Docker Desktop packaging:

- TinyKVM needs Linux KVM access through `/dev/kvm`
- the current `openclaw` package still exposes Docker-backed sandbox settings in its shipped config schema
- so the practical TinyKVM fit today is `OpenClaw gateway on the host` plus `TinyKVM tooling on the same Linux machine`

In other words: this repo no longer pretends that OpenClaw has a native TinyKVM sandbox backend when the current package does not.

## Recommended Topology

- OpenClaw gateway runs directly on a Linux host
- Ollama still runs locally, using the existing [compose.yaml](../compose.yaml) `ollama` service
- OpenClaw sandbox mode is set to `off` so you do not stack Docker sandboxing on top of TinyKVM work
- TinyKVM is used explicitly through the installed `openclaw-tinykvm-run` wrapper for Linux ELF workloads

This is the cleanest current boundary if your goal is “use TinyKVM where it actually helps” instead of keeping the old Dockerized gateway shape.

For the security-focused architecture writeup, see [tinykvm-security-architecture.md](tinykvm-security-architecture.md).

## Scripts

- Host setup: [Install-OpenClawTinyKvmHost.sh](../scripts/Install-OpenClawTinyKvmHost.sh)
- Host service hardening: [Apply-OpenClawSystemdHardening.sh](../scripts/Apply-OpenClawSystemdHardening.sh)
- TinyKVM tooling build/install: [Install-TinyKvmTooling.sh](../scripts/Install-TinyKvmTooling.sh)
- Validation: [Validate-OpenClawTinyKvmHost.sh](../scripts/Validate-OpenClawTinyKvmHost.sh)
- TinyKVM runner wrapper: [openclaw-tinykvm-run.sh](../scripts/openclaw-tinykvm-run.sh)
- Runner source: [openclaw_tinykvm_runner.cpp](../tinykvm-runner/openclaw_tinykvm_runner.cpp)

## Quick Start

Build and install the TinyKVM runner:

```bash
./scripts/Install-TinyKvmTooling.sh
```

Install and configure OpenClaw for the Linux host path:

```bash
./scripts/Install-OpenClawTinyKvmHost.sh
```

That installer now applies a user-systemd hardening override to the OpenClaw gateway service by default. If you need to re-apply it manually:

```bash
./scripts/Apply-OpenClawSystemdHardening.sh
```

Validate the final state:

```bash
./scripts/Validate-OpenClawTinyKvmHost.sh
```

Run a Linux ELF under TinyKVM:

```bash
openclaw-tinykvm-run ./my-program
```

## Behavior Notes

- `Install-OpenClawTinyKvmHost.sh` installs OpenClaw from the current official installer if `openclaw` is missing.
- If `OLLAMA_BASE_URL` is already reachable, the installer reuses that existing Ollama instance instead of starting the Docker `ollama` service.
- It uses `openclaw config set ...` instead of writing guessed JSON directly.
- It configures `gateway.mode=local`, `gateway.bind=loopback`, a token-based gateway auth mode, Ollama as the model provider, and `agents.defaults.sandbox.mode=off`.
- It applies a Linux user-systemd hardening override to the host gateway so TinyKVM is not the only security control in the path.
- The TinyKVM runner is for direct Linux binary execution, not for automatic replacement of OpenClaw’s built-in Docker sandbox.

## Limitations

- OpenClaw package support is still centered on Docker sandbox settings in the shipped config/runtime schema.
- The TinyKVM runner currently targets Linux ELF programs, which is the right match for TinyKVM’s userspace-emulation model.
- Non-FHS systems may need `OPENCLAW_TINYKVM_DYNAMIC_LOADER=/path/to/ld-linux-...` and `OPENCLAW_TINYKVM_EXTRA_READ_PREFIXES=/nix/store` so the runner can see the host’s dynamic loader and shared libraries.
- The older Windows packager remains in the repo, but it is not the preferred path if TinyKVM is the goal.
