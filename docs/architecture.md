# Architecture

## BEADS Layout

This packaging uses a BEADS-style decomposition:

- Bootstrap: validate or install Windows prerequisites, WSL2, and Docker Desktop from PowerShell
- Environment: create a predictable `.env` file and stable host persistence directories under `state/`
- Artifacts: use upstream OpenClaw and Ollama container images without vendoring the OpenClaw source tree
- Deploy: pull the configured model, run `openclaw onboard --non-interactive`, and start the gateway
- Smoke test: verify Docker, WSL2, Ollama, and the OpenClaw health endpoint

## Boundary Model

### Windows host

- Runs the primary operator entrypoints in [scripts/Install-OpenClawStack.ps1](/home/jonathan/src/claw/scripts/Install-OpenClawStack.ps1) and [scripts/Invoke-OpenClawDeploymentValidation.ps1](/home/jonathan/src/claw/scripts/Invoke-OpenClawDeploymentValidation.ps1)
- Optionally installs WSL2 and Docker Desktop with `wsl.exe` and `winget`
- Owns the persistent project directory and `state/` bind mounts
- Owns Hyper-V and Packer during VM validation

### WSL2

- Acts as the supported backend for Docker Desktop on Windows
- Remains a host prerequisite and runtime substrate, not the place where this project directly installs OpenClaw
- Is validated by the deployment checks because OpenClaw’s upstream Windows guidance is WSL2-first

### Docker containers

- `ollama`: local model runtime on port `11434`
- `openclaw-gateway`: main OpenClaw gateway exposing `18789` and `18790`
- `openclaw-cli`: operator container used for onboarding and future CLI operations
- `ollama-loopback`: local forwarder that makes `127.0.0.1:11434` resolve inside the gateway network namespace so official OpenClaw Ollama onboarding can run unmodified

## Data And Config Flow

- `.env` controls image tags, ports, timezone, model choice, and bind-mount locations
- `state/openclaw-config` is mounted to `/home/node/.openclaw`
- `state/openclaw-workspace` is mounted to `/home/node/.openclaw/workspace`
- `state/ollama` is mounted to `/root/.ollama`
- The installer pulls the configured model first, then uses OpenClaw onboarding to generate supported config against the local Ollama runtime

## Network Flow

- Windows host reaches Ollama at `http://127.0.0.1:11434`
- Windows host reaches OpenClaw health at `http://127.0.0.1:18789/healthz`
- Inside the OpenClaw namespace, `ollama-loopback` binds `127.0.0.1:11434` and forwards to the `ollama` service
- The OpenClaw CLI container shares the gateway network namespace, so onboarding and future CLI operations see the same loopback endpoint the gateway uses

## Packaging Choice

The stack intentionally stays close to the current upstream OpenClaw Docker model. The main customization is the Ollama loopback sidecar, which exists only to preserve OpenClaw’s native Ollama integration and tool-calling behavior in a multi-container packaged deployment.

## Architecture-Aware Prerequisites

The packaging layer now treats prerequisite installation as a separate concern:

- [Install-OpenClawPrereqs.ps1](/home/jonathan/src/claw/scripts/Install-OpenClawPrereqs.ps1) handles WSL and Docker Desktop
- [Start-OpenClawPortableBundle.ps1](/home/jonathan/src/claw/installer/Start-OpenClawPortableBundle.ps1) selects `x64` or `arm64` payloads at runtime
- [Build-OpenClawPortableBundle.sh](/home/jonathan/src/claw/installer/Build-OpenClawPortableBundle.sh) builds a redistributable bundle tree

This separation is important because Windows on Arm is not just a different CPU target. It changes the Docker Desktop backend constraints and should be packaged with architecture-specific prerequisite assets.

The portable installer scaffold under [installer/README.md](/home/jonathan/src/claw/installer/README.md) sits alongside that model as a copyable Windows entrypoint. It is architecture-aware at launch time so a single bundle can route `x64` and `arm64` machines into the right payload slot without changing the VM validation path.
