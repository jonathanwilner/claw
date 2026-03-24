# Operations Runbook

[简体中文](runbook.zh-CN.md)

## Startup

Normal startup:

```powershell
docker compose up -d ollama openclaw-gateway ollama-loopback
```

Full re-bootstrap:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-OpenClawStack.ps1
```

## Shutdown

```powershell
docker compose down
```

## Health Checks

Check running services:

```powershell
docker compose ps
```

Check health endpoints:

```powershell
Invoke-WebRequest http://127.0.0.1:11434/api/tags -UseBasicParsing
Invoke-WebRequest http://127.0.0.1:18789/healthz -UseBasicParsing
```

Run the packaged validation suite:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-OpenClawDeploymentValidation.ps1 `
  -OllamaUri 'http://127.0.0.1:11434/api/tags' `
  -OpenClawUri 'http://127.0.0.1:18789/healthz' `
  -RequiredContainers openclaw-ollama,openclaw-gateway,openclaw-ollama-loopback
```

## Logs And Diagnostics

```powershell
docker compose logs --tail=200 ollama
docker compose logs --tail=200 openclaw-gateway
docker compose logs --tail=200 ollama-loopback
```

For VM validation failures, collect guest diagnostics from [vm/scripts/guest/Collect-Diagnostics.ps1](../../vm/scripts/guest/Collect-Diagnostics.ps1).

## Upgrade

1. Update the image tags or model choice in `.env` or rerun the installer with new parameters.
2. Run [scripts/Install-OpenClawStack.ps1](../../scripts/Install-OpenClawStack.ps1) again.
3. Re-run deployment validation.

## Rollback

1. Restore the previous image tags in `.env`.
2. Run `docker compose pull`.
3. Run `docker compose up -d`.

The state directories are intentionally persistent so a rollback does not require re-pulling the model unless you choose to wipe `state/`.

## Common Failure Modes

- `docker info` fails: Docker Desktop is installed but not yet running or not fully initialized.
- `wsl.exe` reports no version 2 distributions: WSL exists, but the Windows host is not in the supported runtime state.
- OpenClaw onboarding fails to find Ollama: inspect the `ollama-loopback` container and verify `127.0.0.1:11434` is reachable in the OpenClaw namespace.
- Model pull is slow or times out: the selected model may be too large for local disk, memory, or network conditions.

## Recovery

If generated config is corrupted or the selected model needs to be rebuilt:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-OpenClawStack.ps1 `
  -ResetConfig
```
