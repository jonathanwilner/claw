# Install Guide

## Supported Path

The canonical path is:

1. Windows 11 host
2. WSL2 enabled
3. Docker Desktop using the WSL2 backend
4. PowerShell-driven installer
5. Dockerized `ollama` + `openclaw-gateway`

## Prerequisites

- Windows 11 with virtualization enabled
- Administrative PowerShell if you want the script to install WSL2 or Docker Desktop for you
- Docker Desktop running before the final deployment step
- Enough disk for the selected Ollama model

## First Install

Run from Windows PowerShell in the project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-OpenClawStack.ps1 `
  -InstallWsl `
  -InstallDockerDesktop `
  -Model 'glm-4.7-flash'
```

If WSL2 and Docker Desktop are already installed, use:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-OpenClawStack.ps1 `
  -Model 'glm-4.7-flash'
```

## Portable Bundle Path

If you want a copyable bundle that can be staged on another Windows machine, use the launcher under [installer/README.md](/home/jonathan/src/claw/installer/README.md).

The launcher detects `x64` vs `arm64`, selects the matching payload slot, and then forwards into the existing PowerShell installer:

```powershell
powershell -ExecutionPolicy Bypass -File .\installer\Start-OpenClawPortableBundle.ps1 `
  -InstallWsl `
  -InstallDockerDesktop `
  -Model 'glm-4.7-flash'
```

## What The Installer Does

- Runs [Install-OpenClawPrereqs.ps1](/home/jonathan/src/claw/scripts/Install-OpenClawPrereqs.ps1) when `-InstallWsl` or `-InstallDockerDesktop` is requested
- Verifies Docker access with `docker info`
- Creates `state/openclaw-config`, `state/openclaw-workspace`, and `state/ollama`
- Writes a project-local `.env`
- Pulls the configured container images
- Starts the `ollama` container
- Pulls the configured local model into Ollama
- Starts the OpenClaw gateway services
- Runs official non-interactive OpenClaw onboarding against `http://127.0.0.1:11434`
- Restarts the gateway and runs deployment validation unless `-SkipValidation` is set

## Architecture Notes

- `x64` Windows uses the normal Docker Desktop Windows installer path.
- `arm64` Windows is supported, but Docker Desktop should be treated as `WSL2-only` and `Early Access`.
- The prerequisite installer can sideload the latest official WSL MSI from the Microsoft WSL GitHub release when the inbox `wsl.exe` is only the legacy stub.

## Portable Bundle

To run the packaged installer tree on another machine, use [installer/Start-OpenClawPortableBundle.ps1](/home/jonathan/src/claw/installer/Start-OpenClawPortableBundle.ps1).

The bundle launcher:

- detects `x64` or `arm64`
- selects the matching payload root
- forwards any staged `wsl.msi` and `DockerDesktopInstaller.exe`
- imports any staged `images/*.tar` archives
- restores any staged `ollama-models/ollama-models.tar.gz`
- then invokes [Install-OpenClawStack.ps1](/home/jonathan/src/claw/scripts/Install-OpenClawStack.ps1)
- The portable bundle launcher also exports the resolved architecture and payload root through environment variables for future staged assets

## Verification

Manual checks:

```powershell
docker compose ps
docker compose logs --tail=100 openclaw-gateway
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-OpenClawDeploymentValidation.ps1 `
  -OllamaUri 'http://127.0.0.1:11434/api/tags' `
  -OpenClawUri 'http://127.0.0.1:18789/healthz' `
  -RequiredContainers openclaw-ollama,openclaw-gateway,openclaw-ollama-loopback
```

Expected endpoints:

- Ollama: `http://127.0.0.1:11434/api/tags`
- OpenClaw health: `http://127.0.0.1:18789/healthz`

## Reset Or Reconfigure

To rebuild generated OpenClaw config and workspace state:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-OpenClawStack.ps1 `
  -ResetConfig `
  -Model 'glm-4.7-flash'
```

## Upgrade

1. Update image tags in `.env` or rerun the installer with new image parameters.
2. Run the installer again.
3. Re-run deployment validation.

## Uninstall

```powershell
docker compose down
Remove-Item -Recurse -Force .\state
Remove-Item -Force .\.env
```

If Docker Desktop or WSL2 were installed solely for this stack, remove them separately using normal Windows package management.
