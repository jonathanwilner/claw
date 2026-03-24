# OpenClaw 部署脚手架

[English](README.md)

这个项目现在包含两条路线：

- 传统的 Windows / WSL2 / Docker Desktop 打包部署路径
- 面向 Linux 的 TinyKVM 路径，用于在宿主机上运行 OpenClaw，并在真正合适的地方使用 TinyKVM 工具

原始的 Windows 打包路径仍然保留。新增 TinyKVM 路径，是因为 TinyKVM 需要直接访问 Linux KVM，而当前 OpenClaw 打包形式并没有提供原生 TinyKVM 沙箱后端。

## TinyKVM 路径

请查看 [docs/tinykvm.md](docs/tinykvm.md)。

关于以安全为重点的架构说明，请查看 [docs/tinykvm-security-architecture.md](docs/tinykvm-security-architecture.md)。

主要入口：

- [Install-TinyKvmTooling.sh](scripts/Install-TinyKvmTooling.sh)
- [Install-OpenClawTinyKvmHost.sh](scripts/Install-OpenClawTinyKvmHost.sh)
- [Validate-OpenClawTinyKvmHost.sh](scripts/Validate-OpenClawTinyKvmHost.sh)

该路径：

- 让 OpenClaw 直接在 Linux 上运行，而不是运行在旧的网关容器中
- 保持 Ollama 本地运行
- 关闭 OpenClaw 的 Docker 沙箱模式，避免在 TinyKVM 工作流外再套一层
- 为 Linux ELF 执行安装 `openclaw-tinykvm-run` 包装器

## 传统 Windows 路径

旧的打包路径仍然面向：

- Windows 11 + WSL2 作为受支持的宿主模型
- 使用 WSL2 后端的 Docker Desktop
- `ollama` 作为本地 LLM 运行时
- PowerShell 作为主要安装与运维入口
- 通过 `@tencent-weixin/openclaw-weixin` 提供可选的腾讯微信渠道集成
- Pester 冒烟测试，以及 Hyper-V/Packer 验证脚手架
- 面向现有 `RDPWindows` WinApps 虚拟机的 libvirt/QEMU guest-agent 路径

实现遵循 BEADS 分解方式：

- `B`ootstrap：安装并验证 Windows、WSL2 和 Docker 前置条件
- `E`nvironment：生成稳定的配置、数据和工作区路径
- `A`rtifacts：以可复现的 Compose 栈方式打包 OpenClaw 和 Ollama
- `D`eploy：拉取模型、运行非交互式初始化并启动网关
- `S`moke test：验证 Ollama、OpenClaw 健康检查端点和容器状态

## 仓库结构

- [compose.yaml](compose.yaml)
- [.env.example](.env.example)
- [docs/README.md](docs/README.md)
- [vm/](vm)
- [scripts/](scripts)
- [tests/](tests)

## 默认流程

1. 在 Windows 上运行 PowerShell 安装器。
2. 安装或验证 WSL2 与 Docker Desktop 前置条件。
3. 启动 `ollama` 容器并拉取配置的本地模型。
4. 针对本地 Ollama 端点运行 `openclaw onboard --non-interactive`。
5. 可选安装并启用腾讯微信插件。
6. 自动启动 OpenClaw 网关。
7. 在本机和一次性 Windows Hyper-V 虚拟机中运行冒烟测试。

## 现有虚拟机流程

如果你已经有一个正在运行、名为 `RDPWindows` 的 Windows WinApps 虚拟机，请使用 [Invoke-RDPWindowsBeads.sh](vm/scripts/host/Invoke-RDPWindowsBeads.sh)。它通过 QEMU guest agent 驱动现有来宾，而不是重新创建新的验证虚拟机。

## 重要限制

- OpenClaw 当前的打包方式仍然主要围绕 Docker 沙箱配置，因此本仓库不会把上游并未提供的一流 TinyKVM 沙箱后端说成已经存在。
- Docker 化网关适合打包和重复验证，但它并不是比 OpenClaw 自带专用沙箱容器更强的信任边界。
- 这个仓库是实现脚手架，不内置上游 OpenClaw 源码。
