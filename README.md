# OpenClaw Windows WSL2 Docker Packager

This project packages OpenClaw for Windows-first deployment with:

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

- OpenClaw currently recommends Windows via WSL2 rather than a native Windows runtime.
- The Dockerized gateway is useful for packaging and repeatable validation, but it is not a stronger trust boundary than the dedicated sandbox containers OpenClaw supports.
- This repo is implementation scaffolding. It does not vendor the upstream OpenClaw source tree.
