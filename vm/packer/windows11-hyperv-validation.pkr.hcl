packer {
  required_version = ">= 1.10.0"

  required_plugins {
    hyperv = {
      source  = "github.com/hashicorp/hyperv"
      version = ">= 1.1.5"
    }
  }
}

locals {
  # The scaffold keeps the answer-file surface in repo so the install flow is
  # visible even before the unattended XML is finalized.
  autounattend_path  = "${path.root}/../templates/autounattend.xml"
  staging_root       = "${path.root}/../artifacts/staging"
  docker_guest_path  = "C:/Windows/Temp/claw-validation/DockerDesktopInstaller.exe"
  app_guest_path     = "C:/Windows/Temp/claw-validation/OpenClawPackage.zip"
}

variable "vm_name" {
  type    = string
  default = "claw-win11-validation"
}

variable "win11_iso_url" {
  type    = string
  default = "https://example.invalid/Windows11.iso"
}

variable "win11_iso_checksum" {
  type    = string
  default = "none"
}

variable "switch_name" {
  type    = string
  default = ""
}

variable "memory_mb" {
  type    = number
  default = 8192
}

variable "cpus" {
  type    = number
  default = 4
}

variable "disk_size_mb" {
  type    = number
  default = 102400
}

variable "guest_username" {
  type    = string
  default = "claw"
}

variable "guest_password" {
  type      = string
  sensitive = true
  default   = "Pack3r!ChangeMe"
}

variable "docker_desktop_arguments" {
  type    = string
  default = "install --quiet --accept-license --backend=wsl-2 --always-run-service"
}

variable "app_installer_kind" {
  type    = string
  default = "auto"
}

variable "app_installer_arguments" {
  type    = string
  default = ""
}

variable "smoke_command" {
  type    = string
  default = ""
}

variable "smoke_http_url" {
  type    = string
  default = ""
}

source "hyperv-iso" "windows11_validation" {
  vm_name      = var.vm_name
  generation   = 2
  memory       = var.memory_mb
  cpus         = var.cpus
  disk_size    = var.disk_size_mb
  switch_name  = var.switch_name
  iso_url      = var.win11_iso_url
  iso_checksum = var.win11_iso_checksum

  communicator   = "winrm"
  winrm_username = var.guest_username
  winrm_password = var.guest_password
  winrm_use_ssl  = false
  winrm_insecure = true

  shutdown_command = "shutdown /s /t 0 /f"
  shutdown_timeout = "20m"
}

build {
  sources = ["source.hyperv-iso.windows11_validation"]

  # Copy payloads from the host staging directory into the guest so the guest
  # install scripts never depend on a Windows host path.
  provisioner "file" {
    source      = "${local.staging_root}/DockerDesktopInstaller.exe"
    destination = local.docker_guest_path
  }

  provisioner "file" {
    source      = "${local.staging_root}/OpenClawPackage.zip"
    destination = local.app_guest_path
  }

  # Stage the Windows features needed for WSL2 and Docker Desktop. The feature
  # enablement generally requires a reboot, so the restart boundary is explicit.
  provisioner "powershell" {
    scripts = ["${path.root}/../scripts/guest/Prepare-Windows11Guest.ps1"]
  }

  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  # Install Docker Desktop, then the packaged app payload, then run smoke tests.
  provisioner "powershell" {
    environment_vars = [
      "DOCKER_DESKTOP_INSTALLER_PATH=${local.docker_guest_path}",
      "DOCKER_DESKTOP_ARGUMENTS=${var.docker_desktop_arguments}",
      "APP_INSTALLER_PATH=${local.app_guest_path}",
      "APP_INSTALLER_ARGUMENTS=${var.app_installer_arguments}",
      "APP_INSTALLER_KIND=${var.app_installer_kind}",
      "SMOKE_COMMAND=${var.smoke_command}",
      "SMOKE_HTTP_URL=${var.smoke_http_url}",
    ]

    scripts = [
      "${path.root}/../scripts/guest/Install-DockerDesktop.ps1",
      "${path.root}/../scripts/guest/Install-AppPayload.ps1",
      "${path.root}/../scripts/guest/Test-AppPayload.ps1",
    ]
  }

  # Leave diagnostics collection in the image so it can be rerun after failures
  # or manually invoked from a Hyper-V console session.
  provisioner "powershell" {
    scripts = ["${path.root}/../scripts/guest/Collect-Diagnostics.ps1"]
  }
}
