# VM 验证脚手架

[English](README.md)

本目录保存用于验证 Windows / WSL2 / Docker Desktop 打包应用的 Windows 11 Hyper-V + Packer 脚手架。

它也包含一条面向现有 libvirt 虚拟机 `RDPWindows` 的在线来宾路径，通过 QEMU guest agent 驱动。

## 布局

- `packer/`：Windows 11 验证虚拟机的 Packer 模板
- `artifacts/staging/`：真实构建前在宿主侧使用的负载预置区
- `scripts/host/`：Hyper-V 宿主侧编排脚本
- `scripts/host/Invoke-RDPWindowsBeads.sh`：Linux/libvirt 宿主上现有 `RDPWindows` 虚拟机的 BEADS runner
- `scripts/host/rdpwindows_guest_agent.py`：在线虚拟机 runner 使用的轻量 QEMU guest-agent 客户端
- `scripts/guest/`：来宾侧的准备、安装、冒烟测试与诊断脚本
- `templates/`：占位用无人值守安装与引导模板

## 目标

该脚手架的范围刻意收窄为：

- 在 CI 中验证 Packer 配置
- 在 Hyper-V 宿主上创建可重复的 Windows 11 来宾
- 在来宾内预置 WSL2 与 Docker Desktop
- 当真实安装路径接通后，安装打包应用负载
- 运行冒烟检查，证明 WSL2/Docker 边界健康

## 假设

- 真正的 Windows 11 ISO 与 Docker Desktop 安装器由调用方提供
- 默认情况下，宿主包装器会打包当前仓库并将其作为应用负载
- 宿主包装器会先把安装器复制到 `artifacts/staging/`，再由 Packer 上传到来宾
- 完整 VM 构建/预配在 Windows Hyper-V 宿主上执行，而不是在 GitHub Actions 中执行
- CI 仅检查格式和语法，不会真正构建 Hyper-V 虚拟机

## 宿主流程

1. 在装有 Hyper-V 和 Packer 的 Windows 机器上运行 `scripts/host/Invoke-VmValidation.ps1`
2. 如果需要完整构建，把 Windows 11 ISO 和 Docker Desktop 安装器路径传给它
3. 可以可选覆盖应用负载路径；否则默认把当前仓库打包为 zip 并作为负载
4. 让 Packer 创建虚拟机并执行来宾脚本
5. 如果冒烟测试失败，通过 `scripts/guest/Collect-Diagnostics.ps1` 收集日志

## 在线 RDPWindows 流程

1. 运行 `scripts/host/Invoke-RDPWindowsBeads.sh --step check`
2. 单独执行 `bootstrap`、`environment`、`artifacts`、`deploy` 和 `smoke`，或者直接 `--step all`
3. 如果来宾尚未安装 Docker Desktop，传入 `--docker-installer-path`
4. 使用现有 guest-agent 与 WinApps/RDP 路径，而不是重新构建新虚拟机

## 来宾流程

1. 启用 WSL 及 Docker Desktop 所需的 Windows 功能
2. 使用 WSL2 后端安装 Docker Desktop
3. 解压打包项目负载并运行 `scripts/Install-OpenClawStack.ps1`
4. 运行冒烟检查，并留下可供收集的日志

## 说明

- Windows 宿主自动化应保留在 `scripts/host/` 中
- 来宾安装流程应保持幂等并可重复执行
- `packer/windows11-hyperv-validation.pkr.hcl` 中的占位值应视为真实构建时必须覆盖的参数
