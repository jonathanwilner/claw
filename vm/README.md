# VM Validation Scaffold

This directory holds the Windows 11 Hyper-V + Packer harness for validating the packaged Windows / WSL2 / Docker Desktop app.

It also contains a live-guest path for an existing libvirt VM named `RDPWindows`, driven through the QEMU guest agent.

## Layout

- `packer/` - Packer template for the Windows 11 validation VM.
- `artifacts/staging/` - Host-side payload staging area used before a real build.
- `scripts/host/` - Host-side orchestration scripts for a Hyper-V machine.
- `scripts/host/Invoke-RDPWindowsBeads.sh` - Host-side BEADS runner for the existing `RDPWindows` VM on a Linux/libvirt host.
- `scripts/host/rdpwindows_guest_agent.py` - Thin QEMU guest-agent client used by the live VM runner.
- `scripts/guest/` - Guest-side setup, install, smoke-test, and diagnostics scripts.
- `templates/` - Placeholder unattended-install and bootstrap templates.

## Intent

The scaffold is intentionally narrow:

- validate the Packer configuration in CI
- create a repeatable Windows 11 guest on a Hyper-V host
- stage WSL2 and Docker Desktop inside the guest
- install the packaged app payload once the real installer path is wired in
- run smoke checks that prove the WSL2/Docker boundary is healthy

## Assumptions

- The real Windows 11 ISO and Docker Desktop installer are supplied by the caller.
- By default, the host wrapper zips the current repository and stages it as the app payload.
- The host wrapper copies installers into `artifacts/staging/` before Packer uploads them into the guest.
- Full VM build/provisioning runs on a Windows Hyper-V host, not in GitHub Actions.
- CI only checks formatting and syntax; it does not attempt a Hyper-V build.

## Host Flow

1. Run `scripts/host/Invoke-VmValidation.ps1` on a Windows machine with Hyper-V and Packer installed.
2. Point it at the Windows 11 ISO and Docker Desktop installer when you want a full build.
3. Optionally override the app payload path; otherwise the current repo is zipped and used as the packaged payload.
4. Let Packer create the VM and run the guest scripts.
5. Collect logs from `scripts/guest/Collect-Diagnostics.ps1` if the smoke test fails.

## Live RDPWindows Flow

1. Run `scripts/host/Invoke-RDPWindowsBeads.sh --step check`.
2. Run `bootstrap`, `environment`, `artifacts`, `deploy`, and `smoke` individually or as `--step all`.
3. Pass `--docker-installer-path` if Docker Desktop is not already installed in the guest.
4. Use the existing guest-agent and WinApps/RDP paths instead of building a new VM.

## Guest Flow

1. Enable WSL and the Windows feature set needed by Docker Desktop.
2. Install Docker Desktop with the WSL2 backend.
3. Expand the packaged project payload and run `scripts/Install-OpenClawStack.ps1`.
4. Run the smoke checks and leave logs behind for collection.

## Notes

- Keep Windows host automation in `scripts/host/`.
- Keep guest setup idempotent and tolerant of re-runs.
- Treat the placeholder values in `packer/windows11-hyperv-validation.pkr.hcl` as required overrides for real builds.
