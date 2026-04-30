---
title: "Letter: HP Request for OpenClaw for Windows"
subtitle: "30-day Microsoft preview with HP launch PR partnership"
author: "HP Personal Systems"
date: "2026-04-29"
mainfont: "DejaVu Serif"
geometry: margin=0.65in
fontsize: 10pt
colorlinks: true
linkcolor: blue
urlcolor: blue
---

# Letter

**To:** Microsoft Windows, WSL, VS Code, Containers, Teams, Copilot, and Security leadership  
**From:** HP Personal Systems  
**Subject:** Request to build and announce an OpenClaw for Windows 30-day preview

Dear Microsoft colleagues,

HP is asking Microsoft to partner with us on a fast, practical **OpenClaw for Windows Preview** that can be announced and made available within **30 days**. The objective is simple: make Windows the easiest, safest, and most visible platform for developers and enterprises to run OpenClaw and local agent workflows with a one-click Windows experience.

We are asking Microsoft to build the preview using existing Microsoft platform strengths: Windows, WSL2, Hyper-V, Windows Containers where appropriate, VS Code, Teams, Copilot/GitHub surfaces where approved, and Windows security controls. The preview should support both **x64 and Arm64** Windows PCs at launch.

The launch should be broadly available to Windows users if Microsoft builds it. HP is not asking for product exclusivity. We are asking for **exclusive launch PR and announcement partnership** so HP can be the featured PC/OEM partner for the first wave of device validation, positioning, customer storytelling, and go-to-market amplification.

The preview should deliver a clear Windows-first outcome: one-click install, validated Windows feature readiness, safe OpenClaw defaults, provider-ready CLI, local model support, VS Code workspace integration, Teams and WhatsApp-style channel use cases, diagnostics, rollback, and explicit security boundaries.

Speed is the key product requirement. This should be scoped as a **30-day preview**, not a full GA platform release. NPU detection and future acceleration are welcome, but they should not slow down the release. The first release should favor a working signed installer, reliable x64/Arm64 validation, clear diagnostics, safe defaults, and a credible roadmap over broad enterprise certification on day one.

If Microsoft cannot own the build and release within the 30-day window, HP is prepared to build and release the Windows bundle independently. In that path, we would still value Microsoft technical validation, recommended guidance, and launch coordination where possible.

The appendix below provides the requested technical requirements for the preview. We would welcome a Microsoft owner across Windows/WSL, VS Code, Containers, Teams, Copilot/GitHub integration, and Security to confirm the fastest path to ship.

Respectfully,  
HP Personal Systems

\newpage

```{=openxml}
<w:p><w:r><w:br w:type="page"/></w:r></w:p>
```

# Appendix A: Day-30 Objective

- Ship a Microsoft-built **OpenClaw for Windows Preview** within 30 days.
- If Microsoft cannot meet the timeline, enable HP to ship an independent Windows bundle with Microsoft guidance where possible.
- Make HP the exclusive launch PR and announcement partner, not the exclusive product distributor.
- Support both x64 and Arm64 Windows PCs at launch.
- Use existing Microsoft product surfaces rather than waiting for new platform work.
- Treat NPU acceleration as optional future value; do not make it a preview blocker.
- Keep the first release preview-scoped: signed installer, validated workflow, diagnostics, rollback, documentation, and support boundaries.
- Defer full GA claims, Store certification, Intune certification, marketplace approval, and broad enterprise support until after the preview proves demand and support load.

# Appendix B: Installer And Payload

- Provide a signed x64 and Arm64 installer, preferably EXE/MSI plus Winget manifest.
- Detect architecture, admin rights, reboot state, virtualization, WSL feature state, VirtualMachinePlatform, Hyper-V capability, Windows Containers feature state, container runtime state, firewall state, VS Code presence, and available disk space.
- Install or validate WSL2 using the supported Microsoft WSL path.
- Install or validate Docker Desktop with WSL2 backend, or a Microsoft-supported equivalent container runtime if available.
- Stage arch-specific payloads for x64 and Arm64.
- Include WSL MSI where needed, container-runtime installer pointer or staged installer where licensing allows, OpenClaw/Ollama image archives, optional model archive, VS Code workspace assets, diagnostics scripts, and rollback metadata.
- Provide an offline enterprise ZIP for constrained environments.
- Preserve user data by default on uninstall, with an explicit option to remove config, models, logs, and workspaces.

# Appendix C: Runtime Architecture

- Run OpenClaw and Ollama in Linux containers through WSL2 for the day-30 path.
- Use Windows Containers only for Windows-side helper services, validation, or sandbox experiments where appropriate.
- Do not imply Windows Containers run Linux OpenClaw images.
- Provide a Compose or equivalent runtime profile for OpenClaw gateway, local model runtime, CLI, loopback bridge, persistent volumes, and health checks.
- Bind local model services to loopback by default.
- Bind OpenClaw gateway to loopback by default and require explicit opt-in for LAN exposure.
- Generate and require a gateway token by default.
- Keep persistent storage for OpenClaw config, OpenClaw workspace, local models, logs, and diagnostics.
- Include health checks for WSL2 distro, container runtime, local model runtime, OpenClaw gateway, loopback bridge, ports, token config, and restart state.

# Appendix D: CLI And VS Code

- Ship one Windows command: `openclaw-win`.
- Required CLI verbs: `doctor`, `install`, `start`, `stop`, `restart`, `logs`, `provider configure`, `channel configure`, `update`, `rollback`, `collect-diagnostics`, and `uninstall`.
- Store provider tokens in Windows Credential Manager or DPAPI rather than plaintext config by default.
- Generate a VS Code workspace that works from both Windows and WSL2.
- Include `.code-workspace`, `.vscode/extensions.json`, `tasks.json`, `launch.json`, PowerShell terminal profile, WSL terminal profile, container context setup, `.devcontainer/devcontainer.json`, and first-run walkthrough.
- Add VS Code tasks for start, stop, logs, doctor, provider setup, channel setup, and diagnostics collection.
- Make failures actionable: every failed check should report cause, fix command, log path, and support bundle path.

\newpage

# Appendix E: Provider Requirements

- Day-30 local provider: Ollama and local OpenAI-compatible endpoint.
- Day-30 remote providers: Anthropic Claude and OpenAI-compatible APIs.
- GitHub Copilot or Copilot Chat should be supported only through approved Microsoft/GitHub product APIs.
- If Copilot API approval is not available, ship the provider slot and documentation rather than a private or unsupported integration.
- Include model/runtime detection for local endpoints such as Ollama, LM Studio, llama.cpp, and vLLM where practical.
- Include NPU capability detection if available, but do not require NPU inference support for the preview.

# Appendix F: Messaging And Remote-Control Use Cases

- Use QClaw/WeChat-style adoption patterns as a product benchmark, not as a bundled dependency.
- Required use cases: phone or chat command, approval prompt, local PC execution, file handoff, status reply, audit trail, and safe cancellation.
- Teams preview: bot package, personal scope, group chat scope, channel scope, message extension actions, Adaptive Card approvals, tenant-admin controls, and command handoff to an authenticated local OpenClaw bridge.
- WhatsApp preview: WhatsApp Business Cloud API webhook adapter sample, webhook signature verification, approval prompts, rate limits, and no scraping of personal WhatsApp sessions.
- China partner path: documented channel adapter API so Tencent/QClaw/WeChat partners can integrate under local policy without Microsoft or HP bundling that code globally.
- Channel adapters must be disableable by policy and off by default in enterprise mode.

# Appendix G: Security Requirements

- Define separate trust zones for gateway, model runtime, workspace, credentials, channel adapters, plugins, and execution sandbox.
- Default to loopback-only networking and generated gateway token.
- Require explicit user or admin action for LAN exposure.
- Use Windows Firewall rules that match the selected exposure mode.
- Store secrets in Windows Credential Manager or DPAPI.
- Provide TinyKVM-class isolation intent through Windows-native controls: Hyper-V isolation, Windows Sandbox where appropriate, VBS, WDAC/AppLocker, Defender, and least-privilege service identities.
- Provide filesystem allowlists for workspace access and protected path denylists for user secrets, browser profiles, payment data, SSH keys, cloud credentials, and system directories.
- Add audit events for prompt execution, skill execution, scripts, payment-adjacent actions, credential reads, clipboard, screen, microphone, camera, filesystem access, and network exposure changes.
- Produce signed artifacts, SBOMs, pinned image digests, rollback metadata, and diagnostics bundles.
- Align deterministic policy checks with Microsoft agent-governance guidance where applicable.

# Appendix H: Validation And Release Gates

- `openclaw-win doctor` must produce a pass/fail report for WSL2, container runtime, Hyper-V, Windows Containers feature state, VS Code, providers, ports, tokens, health endpoints, logs, and firewall exposure.
- Include PowerShell tests for installer and validation helpers.
- Include VM validation for the Windows install path.
- Validate x64 and Arm64 separately.
- Validate fresh install, upgrade, rollback, uninstall-preserve-data, uninstall-remove-data, offline install, and diagnostics collection.
- Validate Teams preview and WhatsApp preview as samples, not production marketplace-approved integrations.
- Validate that the default gateway is not exposed beyond loopback.
- Validate that provider tokens are not written to plaintext config by default.
