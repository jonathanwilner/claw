#!/usr/bin/env python3

import argparse
import http.server
import json
import os
import shutil
import socketserver
import subprocess
import tempfile
import threading
from pathlib import Path

from rdpwindows_guest_agent import GuestAgentError, RdpWindowsGuestAgent


class StagingServer:
    def __init__(self, directory: Path, bind_host: str, port: int) -> None:
        self.directory = directory
        self.bind_host = bind_host
        self.port = port
        self._httpd = None
        self._thread = None

    def __enter__(self):
        handler = http.server.SimpleHTTPRequestHandler
        os.chdir(self.directory)
        self._httpd = socketserver.TCPServer((self.bind_host, self.port), handler)
        self._thread = threading.Thread(target=self._httpd.serve_forever, daemon=True)
        self._thread.start()
        return self

    def __exit__(self, exc_type, exc, tb):
        if self._httpd is not None:
            self._httpd.shutdown()
            self._httpd.server_close()


def run_checked(result: dict, label: str) -> None:
    if result["exitcode"] != 0:
        raise GuestAgentError(
            f"{label} failed with exit code {result['exitcode']}\n"
            f"STDOUT:\n{result['stdout']}\nSTDERR:\n{result['stderr']}"
        )


def write_json(label: str, data: dict) -> None:
    print(f"==> {label}")
    print(json.dumps(data, indent=2))


def build_repo_zip(project_root: Path, staging_dir: Path) -> Path:
    archive_base = staging_dir / "OpenClawPackage"
    archive_path = shutil.make_archive(str(archive_base), "zip", root_dir=project_root)
    return Path(archive_path)


def bootstrap_step(guest: RdpWindowsGuestAgent, distro: str, reboot_timeout: int) -> None:
    command = rf"""
$ErrorActionPreference = 'Stop'
$features = @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')
$changed = $false
foreach ($feature in $features) {{
  $info = dism.exe /online /Get-FeatureInfo /FeatureName:$feature | Out-String
  if ($info -notmatch 'State : Enabled') {{
    dism.exe /online /Enable-Feature /FeatureName:$feature /All /NoRestart | Out-Host
    $changed = $true
  }}
}}
if ($changed) {{
  Write-Host 'REBOOT_REQUIRED'
}} else {{
  Write-Host 'FEATURES_ALREADY_ENABLED'
}}
"""
    result = guest.powershell(command, timeout=600)
    run_checked(result, "Enable WSL2 features")

    if "REBOOT_REQUIRED" in result["stdout"]:
        guest.reboot()
        guest.wait_for_ping(timeout=reboot_timeout)

    sideload_command = rf"""
$ErrorActionPreference = 'Stop'
$stdoutPath = Join-Path $env:TEMP 'openclaw-wsl-version.out'
$stderrPath = Join-Path $env:TEMP 'openclaw-wsl-version.err'
Remove-Item -LiteralPath $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue
$versionProcess = Start-Process -FilePath 'wsl.exe' -ArgumentList @('--version') -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
$message = (((Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue))).Replace("`0", '').Trim()
if ($versionProcess.ExitCode -ne 0) {{
  if ($message -match 'Windows Subsystem for Linux is not installed') {{
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {{ 'arm64' }} else {{ 'x64' }}
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/WSL/releases/latest'
    $asset = $release.assets | Where-Object {{ $_.name -like ('*.' + $arch + '.msi') }} | Select-Object -First 1
    if (-not $asset) {{
      throw \"No WSL MSI asset found for architecture $arch in release $($release.tag_name)\"
    }}
    $downloadDir = 'C:\OpenClawPackage'
    New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
    $msiPath = Join-Path $downloadDir $asset.name
    Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $msiPath
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', $msiPath, '/qn', '/norestart') -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -notin 0, 3010) {{
      throw \"WSL MSI install failed with exit code $($process.ExitCode)\"
    }}
  }} else {{
    throw $message
  }}
}}
$installOut = Join-Path $env:TEMP 'openclaw-wsl-install.out'
$installErr = Join-Path $env:TEMP 'openclaw-wsl-install.err'
Remove-Item -LiteralPath $installOut,$installErr -Force -ErrorAction SilentlyContinue
$installProcess = Start-Process -FilePath 'wsl.exe' -ArgumentList @('--install', '-d', '{distro}') -Wait -PassThru -NoNewWindow -RedirectStandardOutput $installOut -RedirectStandardError $installErr
if ($installProcess.ExitCode -ne 0) {{
  $installMessage = (((Get-Content -LiteralPath $installOut -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content -LiteralPath $installErr -Raw -ErrorAction SilentlyContinue))).Replace("`0", '').Trim()
  throw $installMessage
}}
"""
    install_result = guest.powershell(sideload_command, timeout=5400)
    run_checked(install_result, "Install WSL distribution")


def environment_step(guest: RdpWindowsGuestAgent) -> None:
    command = r"""
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path C:\OpenClawPackage | Out-Null
New-Item -ItemType Directory -Force -Path C:\OpenClawState | Out-Null
"""
    run_checked(guest.powershell(command), "Prepare guest directories")


def artifacts_step(
    guest: RdpWindowsGuestAgent,
    host_ip: str,
    port: int,
    package_name: str,
    docker_installer_name: str | None,
) -> None:
    command = rf"""
$ErrorActionPreference = 'Stop'
Invoke-WebRequest -UseBasicParsing -Uri 'http://{host_ip}:{port}/{package_name}' -OutFile 'C:\OpenClawPackage\{package_name}'
"""
    if docker_installer_name:
        command += rf"""
Invoke-WebRequest -UseBasicParsing -Uri 'http://{host_ip}:{port}/{docker_installer_name}' -OutFile 'C:\OpenClawPackage\{docker_installer_name}'
"""
    run_checked(guest.powershell(command, timeout=1800), "Download staged artifacts")


def deploy_step(
    guest: RdpWindowsGuestAgent,
    model: str,
    docker_installer_name: str | None,
) -> None:
    docker_command = r"""
$ErrorActionPreference = 'Stop'
$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) {
  $installer = 'C:\OpenClawPackage\DockerDesktopInstaller.exe'
  if (-not (Test-Path -LiteralPath $installer)) {
    throw 'Docker Desktop is not installed and no staged installer was found.'
  }
  Start-Process -FilePath $installer -ArgumentList @('install', '--quiet', '--accept-license', '--backend=wsl-2', '--always-run-service') -Wait -NoNewWindow
}
if (Get-Service -Name 'com.docker.service' -ErrorAction SilentlyContinue) {
  Start-Service -Name 'com.docker.service' -ErrorAction SilentlyContinue
}
"""
    if docker_installer_name:
        run_checked(guest.powershell(docker_command, timeout=3600), "Install Docker Desktop")

    command = rf"""
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath C:\OpenClawPackage\repo) {{
  Remove-Item -LiteralPath C:\OpenClawPackage\repo -Recurse -Force
}}
Expand-Archive -Path C:\OpenClawPackage\OpenClawPackage.zip -DestinationPath C:\OpenClawPackage\repo -Force
$installScript = 'C:\OpenClawPackage\repo\scripts\Install-OpenClawStack.ps1'
if (-not (Test-Path -LiteralPath $installScript)) {{
  throw "Install script not found at $installScript"
}}
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installScript -ProjectRoot C:\OpenClawPackage\repo -Model '{model}'
if ($LASTEXITCODE -ne 0) {{
  throw "Install-OpenClawStack.ps1 exited with code $LASTEXITCODE"
}}
"""
    run_checked(guest.powershell(command, timeout=7200), "Run OpenClaw installer")


def smoke_step(guest: RdpWindowsGuestAgent) -> None:
    command = r"""
$ErrorActionPreference = 'Stop'
$validation = 'C:\OpenClawPackage\repo\scripts\Invoke-OpenClawDeploymentValidation.ps1'
if (-not (Test-Path -LiteralPath $validation)) {
  throw "Validation script not found at $validation"
}
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $validation `
  -OllamaUri 'http://127.0.0.1:11434/api/tags' `
  -OpenClawUri 'http://127.0.0.1:18789/healthz' `
  -RequiredContainers @('openclaw-ollama','openclaw-gateway','openclaw-ollama-loopback') `
  -AsJson
if ($LASTEXITCODE -ne 0) {
  throw "Deployment validation exited with code $LASTEXITCODE"
}
"""
    run_checked(guest.powershell(command, timeout=900), "Smoke validation")


def check_step(guest: RdpWindowsGuestAgent) -> None:
    command = r"""
[PSCustomObject]@{
  Hostname = $env:COMPUTERNAME
  PSVersion = $PSVersionTable.PSVersion.ToString()
  Winget = (Get-Command winget -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
  Docker = (Get-Command docker -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
  Wsl = (Get-Command wsl.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
  DockerService = (Get-Service -Name 'com.docker.service' -ErrorAction SilentlyContinue | Select-Object Name,Status)
  WslStatus = ((wsl.exe --status) 2>&1 | Out-String)
} | ConvertTo-Json -Depth 4
"""
    result = guest.powershell(command, timeout=300)
    run_checked(result, "Guest readiness probe")
    print(result["stdout"])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vm-name", default="RDPWindows")
    parser.add_argument(
        "--project-root",
        default=str(Path(__file__).resolve().parents[3]),
    )
    parser.add_argument("--host-ip", default="192.168.122.1")
    parser.add_argument("--http-port", type=int, default=18080)
    parser.add_argument("--model", default="glm-4.7-flash")
    parser.add_argument("--distro", default="Ubuntu")
    parser.add_argument("--docker-installer-path")
    parser.add_argument(
        "--step",
        choices=["check", "bootstrap", "environment", "artifacts", "deploy", "smoke", "all"],
        default="check",
    )
    parser.add_argument("--reboot-timeout", type=int, default=900)
    args = parser.parse_args()

    project_root = Path(args.project_root).resolve()
    guest = RdpWindowsGuestAgent(vm_name=args.vm_name)
    guest.ping()

    if args.step == "check":
        check_step(guest)
        return 0

    staging_parent = Path(tempfile.mkdtemp(prefix="claw-rdpwindows-"))
    staging_dir = staging_parent / "staging"
    staging_dir.mkdir(parents=True, exist_ok=True)

    package_zip = build_repo_zip(project_root, staging_dir)
    docker_installer_name = None
    if args.docker_installer_path:
        docker_src = Path(args.docker_installer_path).resolve()
        docker_installer_name = docker_src.name
        shutil.copy2(docker_src, staging_dir / docker_installer_name)

    steps = (
        ["bootstrap", "environment", "artifacts", "deploy", "smoke"]
        if args.step == "all"
        else [args.step]
    )

    with StagingServer(staging_dir, bind_host="0.0.0.0", port=args.http_port):
        for step in steps:
            print(f"==> BEADS step: {step}")
            if step == "bootstrap":
                bootstrap_step(guest, distro=args.distro, reboot_timeout=args.reboot_timeout)
            elif step == "environment":
                environment_step(guest)
            elif step == "artifacts":
                artifacts_step(
                    guest,
                    host_ip=args.host_ip,
                    port=args.http_port,
                    package_name=package_zip.name,
                    docker_installer_name=docker_installer_name,
                )
            elif step == "deploy":
                deploy_step(guest, model=args.model, docker_installer_name=docker_installer_name)
            elif step == "smoke":
                smoke_step(guest)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
