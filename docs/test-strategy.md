# Test Strategy

## Goals

The validation strategy is split across three layers:

- TinyKVM host validation on Linux
- fast PowerShell logic checks
- host-level deployment smoke tests on Windows
- full packaging validation in a disposable Windows 11 Hyper-V VM

## TinyKVM Host Layer

For the Linux / TinyKVM path, run:

```bash
./scripts/Validate-OpenClawTinyKvmHost.sh
```

That checks:

- `/dev/kvm` presence and access
- installed TinyKVM runner binaries
- Ollama reachability
- OpenClaw gateway status and health
- model visibility from the current OpenClaw config

## Local Test Layer

The Pester suite in [tests/OpenClaw.DeploymentValidation.Tests.ps1](/home/jonathan/src/claw/tests/OpenClaw.DeploymentValidation.Tests.ps1) verifies the reusable validation helpers:

- normalized check objects
- parsing of `wsl.exe -l -v`
- deployment summary generation

These are the fastest tests and do not require a running Docker stack.

## Host Smoke Layer

The deployment validation wrapper in [scripts/Invoke-OpenClawDeploymentValidation.ps1](/home/jonathan/src/claw/scripts/Invoke-OpenClawDeploymentValidation.ps1) checks:

- PowerShell runtime availability
- WSL2 visibility
- Docker CLI and daemon health
- required running containers
- HTTP reachability for Ollama and OpenClaw

Recommended command:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-OpenClawDeploymentValidation.ps1 `
  -OllamaUri 'http://127.0.0.1:11434/api/tags' `
  -OpenClawUri 'http://127.0.0.1:18789/healthz' `
  -RequiredContainers openclaw-ollama,openclaw-gateway,openclaw-ollama-loopback
```

## VM Validation Layer

The Hyper-V/Packer harness under [vm/README.md](/home/jonathan/src/claw/vm/README.md) is the release-grade packaging check:

- stage a Windows 11 guest
- install or validate Windows prerequisites
- install Docker Desktop
- stage the packaged repo payload
- run [scripts/Install-OpenClawStack.ps1](/home/jonathan/src/claw/scripts/Install-OpenClawStack.ps1) inside the guest
- confirm WSL2, Docker Desktop, and OpenClaw health inside the guest

This is the closest approximation of a fresh user install.

## CI Gate

The workflow at [.github/workflows/vm-validation.yml](/home/jonathan/src/claw/.github/workflows/vm-validation.yml) is intentionally syntax-only:

- `packer init`
- `packer fmt -check`
- `packer validate`
- PowerShell parse checks for the VM scripts

It does not attempt nested virtualization or a real Hyper-V build.

## Release Gate

Before treating a change as release-ready:

- Pester validation should pass on a Windows machine with PowerShell and Pester available
- local host smoke validation should pass after install
- the Hyper-V/Packer flow should complete on a real Windows host with staged installers
