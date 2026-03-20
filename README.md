# OpenClaw Deployment Scaffold

This project now has two tracks:

- a legacy Windows / WSL2 / Docker Desktop packaging path
- a Linux-first TinyKVM path for running OpenClaw on the host and using TinyKVM tooling where it actually fits

The original Windows packaging is still here. The new TinyKVM path exists because TinyKVM wants direct Linux KVM access, and the current OpenClaw package does not ship a native TinyKVM sandbox backend.

## TinyKVM Path

Use the TinyKVM guide at [docs/tinykvm.md](/home/jonathan/src/claw/docs/tinykvm.md).

The main entrypoints are:

- [Install-TinyKvmTooling.sh](/home/jonathan/src/claw/scripts/Install-TinyKvmTooling.sh)
- [Install-OpenClawTinyKvmHost.sh](/home/jonathan/src/claw/scripts/Install-OpenClawTinyKvmHost.sh)
- [Validate-OpenClawTinyKvmHost.sh](/home/jonathan/src/claw/scripts/Validate-OpenClawTinyKvmHost.sh)

That path:

- runs OpenClaw directly on Linux instead of inside the old gateway container
- keeps Ollama local
- disables OpenClaw’s Docker sandbox mode to avoid double-wrapping TinyKVM work
- installs an `openclaw-tinykvm-run` wrapper for Linux ELF execution

## Legacy Windows Path

The older packaging path still targets:

- Windows 11 + WSL2 as the supported host model
- Docker Desktop with the WSL2 backend
- `ollama` as the local LLM runtime
- PowerShell as the primary installer and operator surface
- Pester smoke tests plus a Hyper-V/Packer validation harness
- a live libvirt/QEMU guest-agent path for an existing `RDPWindows` WinApps VM

The implementation follows a BEADS-style decomposition:

- `B`ootstrap: install and validate Windows, WSL2, and Docker prerequisites
- `E`nvironment: generate stable config, data, and workspace paths
- `A`rtifacts: package OpenClaw and Ollama in a reproducible Compose stack
- `D`eploy: pull the model, run non-interactive onboarding, and start the gateway
- `S`moke test: verify Ollama, the OpenClaw health endpoint, and container status

## Repository Layout

- [compose.yaml](/home/jonathan/src/claw/compose.yaml)
- [.env.example](/home/jonathan/src/claw/.env.example)
- [docs/README.md](/home/jonathan/src/claw/docs/README.md)
- [vm/](/home/jonathan/src/claw/vm)
- [scripts/](/home/jonathan/src/claw/scripts)
- [tests/](/home/jonathan/src/claw/tests)

## Default Flow

1. Run the PowerShell installer on Windows.
2. Install or validate WSL2 and Docker Desktop prerequisites.
3. Start the `ollama` container and pull the configured local model.
4. Run `openclaw onboard --non-interactive` against the local Ollama endpoint.
5. Start the OpenClaw gateway automatically.
6. Run smoke tests locally and in a disposable Windows Hyper-V VM.

## Existing VM Flow

If you already have a running Windows WinApps VM named `RDPWindows`, use the BEADS runner at [Invoke-RDPWindowsBeads.sh](/home/jonathan/src/claw/vm/scripts/host/Invoke-RDPWindowsBeads.sh). It drives the live guest through the QEMU guest agent instead of building a new VM.

## Important Constraints

- OpenClaw’s current package surface still centers sandbox config around Docker, so this repo does not claim a first-class TinyKVM sandbox backend that upstream does not ship.
- The Dockerized gateway is useful for packaging and repeatable validation, but it is not a stronger trust boundary than the dedicated sandbox containers OpenClaw supports.
- This repo is implementation scaffolding. It does not vendor the upstream OpenClaw source tree.
