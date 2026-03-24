# Portable Installer Bundle

[简体中文](README.zh-CN.md)

This directory is the scaffold for a reusable Windows installer bundle that can be copied to another machine and run locally.

## Layout

- `Build-OpenClawPortableBundle.sh` builds a portable bundle tree on the current host.
- `build_portable_bundle.py` is the cross-platform bundle builder implementation.
- `Export-OpenClawOfflinePayload.sh` exports Docker image archives and an optional Ollama model payload.
- `Start-OpenClawPortableBundle.ps1` is the bundle entrypoint.
- `Test-OpenClawPortableBundle.ps1` runs the packaged deployment validation from the bundle context.
- `BundleManifest.json` describes the bundle metadata and reserved payload roots.
- `payload/x64/` is the staging slot for x64-specific assets.
- `payload/arm64/` is the staging slot for arm64-specific assets.

## How It Works

The bundle launcher:

1. Detects the host architecture at runtime.
2. Selects the matching payload root for `x64` or `arm64`.
3. Resolves a runnable OpenClaw project tree.
4. Supplies optional architecture-matched WSL and Docker installers from the payload root.
5. Forwards into `scripts/Install-OpenClawStack.ps1`, which now uses the shared prerequisite installer path.

This keeps the portable bundle thin while still giving the packaging path an architecture-aware entrypoint.

When payloads are staged, the bundle can also operate in a mostly offline mode:

- `images/*.tar` for Docker image archives
- `ollama-models/ollama-models.tar.gz` for a preloaded Ollama model store
- `npm/*.tgz` for staged plugin tarballs such as `@tencent-weixin/openclaw-weixin`
- `wsl.msi` for the official Microsoft WSL package
- `DockerDesktopInstaller.exe` for Docker Desktop

## Current Scope

- The bundle is a scaffold, not a finalized release artifact.
- It does not modify VM host automation under `vm/`.
- It expects the actual OpenClaw repository contents to be present in the copied tree or provided through `-ProjectRoot`.
- For Windows on Arm, Docker Desktop should be treated as `WSL2-only` and `Early Access`; Windows containers are not part of this path.

## Build A Bundle

From this repo on the current host:

```bash
./installer/Build-OpenClawPortableBundle.sh \
  --project-root /home/jonathan/src/claw \
  --output-root /tmp/openclaw-portable-bundle
```

## Export Offline Payloads

Create an offline payload root for one architecture from a Docker-capable source machine:

```bash
./installer/Export-OpenClawOfflinePayload.sh \
  --output-root /tmp/openclaw-offline-x64 \
  --openclaw-image openclaw/openclaw:latest \
  --ollama-image ollama/ollama:latest \
  --helper-image alpine/socat:1.8.0.3 \
  --weixin-plugin-npm-spec @tencent-weixin/openclaw-weixin \
  --model glm-4.7-flash \
  --ollama-models-dir /path/to/.ollama/models
```

Then include that payload root in the bundle:

```bash
./installer/Build-OpenClawPortableBundle.sh \
  --project-root /home/jonathan/src/claw \
  --output-root /tmp/openclaw-portable-bundle \
  --docker-images-x64-root /tmp/openclaw-offline-x64/images \
  --ollama-model-archive-x64 /tmp/openclaw-offline-x64/ollama-models/ollama-models.tar.gz \
  --weixin-plugin-archive-x64 /tmp/openclaw-offline-x64/npm/tencent-weixin-openclaw-weixin-1.0.3.tgz \
  --wsl-x64 /path/to/wsl.x64.msi \
  --docker-x64 /path/to/DockerDesktopInstaller-x64.exe
```

With staged prerequisite installers:

```bash
./installer/Build-OpenClawPortableBundle.sh \
  --project-root /home/jonathan/src/claw \
  --output-root /tmp/openclaw-portable-bundle \
  --wsl-x64 /path/to/wsl.x64.msi \
  --wsl-arm64 /path/to/wsl.arm64.msi \
  --docker-x64 /path/to/DockerDesktopInstaller-x64.exe \
  --docker-arm64 /path/to/DockerDesktopInstaller-arm64.exe \
  --zip
```

## Example

```powershell
powershell -ExecutionPolicy Bypass -File .\installer\Start-OpenClawPortableBundle.ps1 `
  -InstallWsl `
  -InstallDockerDesktop `
  -InstallWeixinPlugin `
  -Model 'glm-4.7-flash'
```

If the payload root already contains `wsl.msi` and `DockerDesktopInstaller.exe` for the detected architecture, the launcher forwards those to the shared prerequisite installer automatically.

If the payload root also contains `images/*.tar` and `ollama-models/ollama-models.tar.gz`, the installer imports the Docker images, restores the local LLM payload, and then runs the normal OpenClaw validation flow.

## Test The Bundle

After installation:

```powershell
powershell -ExecutionPolicy Bypass -File .\installer\Test-OpenClawPortableBundle.ps1
```

To inspect behavior without running the installer:

```powershell
powershell -ExecutionPolicy Bypass -File .\installer\Start-OpenClawPortableBundle.ps1 -DryRun
```
