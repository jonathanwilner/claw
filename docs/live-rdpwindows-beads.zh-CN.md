# 在线 RDPWindows BEADS

[English](live-rdpwindows-beads.md)

本运行手册覆盖的是现有 libvirt WinApps 虚拟机路径：直接使用已经运行中的 `RDPWindows` 来宾，而不是创建新的验证虚拟机。

## 为什么存在这条路径

宿主机已经有一台运行中的 Windows 11 虚拟机，并具备：

- libvirt system 管理
- 可用的 QEMU guest agent 通道
- 可访问的 RDP 端点
- 现有 WinApps 集成路径

因此最快的受支持实验循环不是 `Packer -> 新 VM`，而是 `guest-agent -> 现有 VM`。

## BEADS 拆解

### B: Bootstrap

Bootstrap 会启用或验证：

- `Microsoft-Windows-Subsystem-Linux`
- `VirtualMachinePlatform`
- `wsl.exe --install --web-download -d Ubuntu`

如果功能启用改变了系统状态，来宾会重启，runner 会等待 QEMU guest agent 恢复。

### E: Environment

环境准备会在来宾中创建稳定路径：

- `C:\OpenClawPackage`
- `C:\OpenClawState`

这些目录用于存放项目 zip、可选 Docker Desktop 安装器以及解压后的仓库树。

### A: Artifacts

构件预置做两件事：

1. 在 Linux 宿主上打包当前仓库为 zip。
2. 用临时 HTTP 服务对外提供 zip，让 Windows 来宾通过现有 libvirt 网络下载。

如果提供 Docker Desktop 安装器路径，也会用同样方式预置该文件。

### D: Deploy

部署阶段执行真正的来宾改动：

- 如果来宾未安装 Docker 且提供了安装器，则安装 Docker Desktop
- 将仓库 zip 解压到 `C:\OpenClawPackage\repo`
- 在来宾中运行 [Install-OpenClawStack.ps1](../scripts/Install-OpenClawStack.ps1)

这是影响最大的步骤。如果你想缩小故障范围，请先单独运行 `check`、`bootstrap`、`environment` 和 `artifacts`。

### S: Smoke

Smoke 会在 Windows 来宾中运行 [Invoke-OpenClawDeploymentValidation.ps1](../scripts/Invoke-OpenClawDeploymentValidation.ps1)，检查：

- `http://127.0.0.1:11434/api/tags`
- `http://127.0.0.1:18789/healthz`

同时验证预期容器名称。

## Runner

主要入口：

- [Invoke-RDPWindowsBeads.sh](../vm/scripts/host/Invoke-RDPWindowsBeads.sh)

底层实现：

- [Invoke-RDPWindowsBeads.py](../vm/scripts/host/Invoke-RDPWindowsBeads.py)
- [rdpwindows_guest_agent.py](../vm/scripts/host/rdpwindows_guest_agent.py)

## 操作步骤

### 1. 检查在线来宾

```bash
./vm/scripts/host/Invoke-RDPWindowsBeads.sh --step check
```

该步骤确认 guest agent 存活，并报告当前 WSL/Docker 状态。

### 2. Bootstrap WSL2

```bash
./vm/scripts/host/Invoke-RDPWindowsBeads.sh --step bootstrap
```

当来宾已有 `wsl.exe`，但 WSL 尚未安装或配置完成时，使用此步骤。

### 3. 准备目录

```bash
./vm/scripts/host/Invoke-RDPWindowsBeads.sh --step environment
```

这是低风险且幂等的。

### 4. 向来宾预置构件

```bash
./vm/scripts/host/Invoke-RDPWindowsBeads.sh --step artifacts
```

如果带 Docker 安装器：

```bash
./vm/scripts/host/Invoke-RDPWindowsBeads.sh \
  --step artifacts \
  --docker-installer-path /path/to/DockerDesktopInstaller.exe
```

### 5. 部署 OpenClaw

```bash
./vm/scripts/host/Invoke-RDPWindowsBeads.sh \
  --step deploy \
  --model glm-4.7-flash \
  --docker-installer-path /path/to/DockerDesktopInstaller.exe
```

### 6. 运行冒烟验证

```bash
./vm/scripts/host/Invoke-RDPWindowsBeads.sh --step smoke
```

### 7. 运行整条链路

```bash
./vm/scripts/host/Invoke-RDPWindowsBeads.sh \
  --step all \
  --model glm-4.7-flash \
  --docker-installer-path /path/to/DockerDesktopInstaller.exe
```

## 当前限制

- runner 假定现有虚拟机名为 `RDPWindows`
- 来宾必须有可工作的 QEMU guest agent
- 部署步骤需要来宾已安装 Docker，或者提供 Docker Desktop 安装器路径
- 在当前宿主上，因已启用嵌套虚拟化且 VM 使用 `host-passthrough`，来宾内运行 WSL2 是有希望的，但 bootstrap 仍需在 Windows 内真正完成
- 在当前 `RDPWindows` 镜像上，可以启用相关 Windows 功能，但来宾没有 `winget`，且 `wsl.exe` 仍表现为旧安装 stub，因此在安装现代 WSL 包之前，自动发行版安装会被卡住
