# Documentation Index

This directory now documents both the older Windows packaging path and the newer Linux / TinyKVM host path.

## Sections

- [TinyKVM Guide](tinykvm.md)
- [TinyKVM Security Architecture](tinykvm-security-architecture.md)
- [Architecture](architecture.md)
- [Install Guide](install.md)
- [Test Strategy](test-strategy.md)
- [Operations Runbook](operations/runbook.md)
- [Live RDPWindows BEADS](live-rdpwindows-beads.md)

## Primary Artifacts

- Installer: [scripts/Install-OpenClawStack.ps1](../scripts/Install-OpenClawStack.ps1)
- TinyKVM host installer: [scripts/Install-OpenClawTinyKvmHost.sh](../scripts/Install-OpenClawTinyKvmHost.sh)
- TinyKVM host hardening: [scripts/Apply-OpenClawSystemdHardening.sh](../scripts/Apply-OpenClawSystemdHardening.sh)
- TinyKVM tooling installer: [scripts/Install-TinyKvmTooling.sh](../scripts/Install-TinyKvmTooling.sh)
- Portable bundle: [installer/README.md](../installer/README.md)
- Validation wrapper: [scripts/Invoke-OpenClawDeploymentValidation.ps1](../scripts/Invoke-OpenClawDeploymentValidation.ps1)
- Compose stack: [compose.yaml](../compose.yaml)
- Environment template: [.env.example](../.env.example)
- VM harness: [vm/README.md](../vm/README.md)

## Execution Model

- Windows owns operator entrypoints and optional prerequisite installation through PowerShell.
- Docker Desktop provides the container runtime using the WSL2 backend.
- Ollama runs as a dedicated container and hosts the local model.
- OpenClaw runs in an upstream-compatible gateway container plus a CLI container for onboarding and operator commands.
- The TinyKVM path instead runs OpenClaw directly on Linux and uses TinyKVM tooling explicitly for Linux ELF execution.
