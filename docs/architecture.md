# Architecture

[简体中文](architecture.zh-CN.md)

## BEADS Layout

This packaging uses a BEADS-style decomposition:

- Bootstrap: validate or install Windows prerequisites, WSL2, and Docker Desktop from PowerShell
- Environment: create a predictable `.env` file and stable host persistence directories under `state/`
- Artifacts: use upstream OpenClaw and Ollama container images without vendoring the OpenClaw source tree
- Deploy: pull the configured model, run `openclaw onboard --non-interactive`, and start the gateway
- Smoke test: verify Docker, WSL2, Ollama, and the OpenClaw health endpoint

## Boundary Model

### Windows host

- Runs the primary operator entrypoints in [scripts/Install-OpenClawStack.ps1](../scripts/Install-OpenClawStack.ps1) and [scripts/Invoke-OpenClawDeploymentValidation.ps1](../scripts/Invoke-OpenClawDeploymentValidation.ps1)
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
- `@tencent-weixin/openclaw-weixin`: optional Tencent channel plugin installed through the OpenClaw CLI container

## Data And Config Flow

- `.env` controls image tags, ports, timezone, model choice, and bind-mount locations
- `state/openclaw-config` is mounted to `/home/node/.openclaw`
- `state/openclaw-workspace` is mounted to `/home/node/.openclaw/workspace`
- `state/ollama` is mounted to `/root/.ollama`
- The installer pulls the configured model first, then uses OpenClaw onboarding to generate supported config against the local Ollama runtime
- If Weixin integration is enabled, the installer then installs the Tencent plugin from npm or a staged tarball and writes packaging metadata to `state/openclaw-config/openclaw-weixin-packaging.json`

## Network Flow

- Windows host reaches Ollama at `http://127.0.0.1:11434`
- Windows host reaches OpenClaw health at `http://127.0.0.1:18789/healthz`
- Inside the OpenClaw namespace, `ollama-loopback` binds `127.0.0.1:11434` and forwards to the `ollama` service
- The OpenClaw CLI container shares the gateway network namespace, so onboarding and future CLI operations see the same loopback endpoint the gateway uses

## Packaging Choice

The stack intentionally stays close to the current upstream OpenClaw Docker model. The main customization is the Ollama loopback sidecar, which exists only to preserve OpenClaw’s native Ollama integration and tool-calling behavior in a multi-container packaged deployment.

## TinyKVM-Optimized Topology

The TinyKVM-oriented path is deliberately different:

- OpenClaw runs on a Linux host instead of inside the packaged gateway container
- Ollama can still stay local, including via the existing [compose.yaml](../compose.yaml) `ollama` service
- OpenClaw sandbox mode is disabled for that path, because the current package surface still exposes Docker sandbox settings rather than a native TinyKVM backend
- The host gateway is hardened separately with a user-systemd override instead of assuming TinyKVM alone protects the control plane
- TinyKVM is installed as host-side tooling and invoked through the local runner wrapper built from [tinykvm-runner/](../tinykvm-runner)

That split is the cleanest current fit for TinyKVM because it avoids stacking the older Dockerized gateway boundary on top of a Linux/KVM-native execution model.

The security-specific reasoning for that split is documented in [tinykvm-security-architecture.md](tinykvm-security-architecture.md).

## Architecture-Aware Prerequisites

The packaging layer now treats prerequisite installation as a separate concern:

- [Install-OpenClawPrereqs.ps1](../scripts/Install-OpenClawPrereqs.ps1) handles WSL and Docker Desktop
- [Start-OpenClawPortableBundle.ps1](../installer/Start-OpenClawPortableBundle.ps1) selects `x64` or `arm64` payloads at runtime
- [Build-OpenClawPortableBundle.sh](../installer/Build-OpenClawPortableBundle.sh) builds a redistributable bundle tree

This separation is important because Windows on Arm is not just a different CPU target. It changes the Docker Desktop backend constraints and should be packaged with architecture-specific prerequisite assets.

The portable installer scaffold under [installer/README.md](../installer/README.md) sits alongside that model as a copyable Windows entrypoint. It is architecture-aware at launch time so a single bundle can route `x64` and `arm64` machines into the right payload slot without changing the VM validation path.
