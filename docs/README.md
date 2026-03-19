# Documentation Index

This directory documents the Windows-first packaged deployment for OpenClaw with Docker Desktop, WSL2, and a local Ollama model runtime.

## Sections

- [Architecture](architecture.md)
- [Install Guide](install.md)
- [Test Strategy](test-strategy.md)
- [Operations Runbook](operations/runbook.md)
- [Live RDPWindows BEADS](live-rdpwindows-beads.md)

## Primary Artifacts

- Installer: [scripts/Install-OpenClawStack.ps1](/home/jonathan/src/claw/scripts/Install-OpenClawStack.ps1)
- Portable bundle: [installer/README.md](/home/jonathan/src/claw/installer/README.md)
- Validation wrapper: [scripts/Invoke-OpenClawDeploymentValidation.ps1](/home/jonathan/src/claw/scripts/Invoke-OpenClawDeploymentValidation.ps1)
- Compose stack: [compose.yaml](/home/jonathan/src/claw/compose.yaml)
- Environment template: [.env.example](/home/jonathan/src/claw/.env.example)
- VM harness: [vm/README.md](/home/jonathan/src/claw/vm/README.md)

## Execution Model

- Windows owns operator entrypoints and optional prerequisite installation through PowerShell.
- Docker Desktop provides the container runtime using the WSL2 backend.
- Ollama runs as a dedicated container and hosts the local model.
- OpenClaw runs in an upstream-compatible gateway container plus a CLI container for onboarding and operator commands.
