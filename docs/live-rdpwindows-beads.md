# Live RDPWindows BEADS

This runbook covers the existing libvirt WinApps VM path using the running `RDPWindows` guest instead of creating a new validation VM.

## Why This Path Exists

The host already has a running Windows 11 VM with:

- libvirt system management
- a working QEMU guest agent channel
- reachable RDP endpoints
- an existing WinApps integration path

That means the fastest supported experiment loop is not `Packer -> new VM`. It is `guest-agent -> existing VM`.

## BEADS Breakdown

### B: Bootstrap

Bootstrap enables or validates:

- `Microsoft-Windows-Subsystem-Linux`
- `VirtualMachinePlatform`
- `wsl.exe --install --web-download -d Ubuntu`

If feature enablement changes system state, the guest is rebooted and the runner waits for the QEMU guest agent to come back.

### E: Environment

Environment preparation creates stable guest paths:

- `C:\OpenClawPackage`
- `C:\OpenClawState`

These hold the staged project zip, optional Docker Desktop installer, and extracted repository tree.

### A: Artifacts

Artifact staging does two things:

1. Zip the current repository on the Linux host.
2. Serve the zip from a temporary host HTTP server so the Windows guest can download it through its existing libvirt network.

If you provide a Docker Desktop installer path, that file is staged the same way.

### D: Deploy

Deploy performs the real guest changes:

- install Docker Desktop if it is not already present and a staged installer is available
- extract the repo zip to `C:\OpenClawPackage\repo`
- run [Install-OpenClawStack.ps1](../scripts/Install-OpenClawStack.ps1) inside the guest

This is the highest-impact step. Run `check`, `bootstrap`, `environment`, and `artifacts` first if you want to narrow failure domains.

### S: Smoke

Smoke runs [Invoke-OpenClawDeploymentValidation.ps1](../scripts/Invoke-OpenClawDeploymentValidation.ps1) inside the Windows guest against:

- `http://127.0.0.1:11434/api/tags`
- `http://127.0.0.1:18789/healthz`

It also verifies the expected container names.

## Runner

Primary entrypoint:

- [Invoke-RDPWindowsBeads.sh](../vm/scripts/host/Invoke-RDPWindowsBeads.sh)

Underlying implementation:

- [Invoke-RDPWindowsBeads.py](../vm/scripts/host/Invoke-RDPWindowsBeads.py)
- [rdpwindows_guest_agent.py](../vm/scripts/host/rdpwindows_guest_agent.py)

## Walkthrough

### 1. Check the live guest

```bash
./vm/scripts/host/Invoke-RDPWindowsBeads.sh --step check
```

This confirms that the guest agent is alive and reports the current WSL/Docker state.

### 2. Bootstrap WSL2

```bash
./vm/scripts/host/Invoke-RDPWindowsBeads.sh --step bootstrap
```

Use this when the guest has `wsl.exe` available but WSL is not yet installed or configured.

### 3. Prepare directories

```bash
./vm/scripts/host/Invoke-RDPWindowsBeads.sh --step environment
```

This is low-risk and idempotent.

### 4. Stage artifacts into the guest

```bash
./vm/scripts/host/Invoke-RDPWindowsBeads.sh --step artifacts
```

With a Docker installer:

```bash
./vm/scripts/host/Invoke-RDPWindowsBeads.sh \
  --step artifacts \
  --docker-installer-path /path/to/DockerDesktopInstaller.exe
```

### 5. Deploy OpenClaw

```bash
./vm/scripts/host/Invoke-RDPWindowsBeads.sh \
  --step deploy \
  --model glm-4.7-flash \
  --docker-installer-path /path/to/DockerDesktopInstaller.exe
```

### 6. Run smoke validation

```bash
./vm/scripts/host/Invoke-RDPWindowsBeads.sh --step smoke
```

### 7. Run the full chain

```bash
./vm/scripts/host/Invoke-RDPWindowsBeads.sh \
  --step all \
  --model glm-4.7-flash \
  --docker-installer-path /path/to/DockerDesktopInstaller.exe
```

## Current Constraints

- The runner assumes the existing VM is named `RDPWindows`.
- The guest must have a working QEMU guest agent.
- The deploy step needs either Docker already installed in the guest or a staged Docker Desktop installer path.
- WSL2 inside the guest is plausible on this host because nested virtualization is enabled and the VM uses `host-passthrough`, but the bootstrap step still needs to complete successfully inside Windows before Docker Desktop can rely on it.
- On the current `RDPWindows` image, the prerequisite Windows features can be enabled, but the guest does not currently have `winget`, and `wsl.exe` behaves like the legacy installer stub. That means automatic WSL distro installation is blocked until the guest has a modern WSL package installation path.
