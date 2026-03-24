# 文档索引

[English](README.md)

本目录现在同时记录两条路线：

- 较旧的 Windows 打包路径
- 较新的 Linux / TinyKVM 宿主路径

## 章节

- [TinyKVM 指南](tinykvm.zh-CN.md)
- [TinyKVM 安全架构](tinykvm-security-architecture.zh-CN.md)
- [架构说明](architecture.zh-CN.md)
- [安装指南](install.zh-CN.md)
- [微信集成](weixin.zh-CN.md)
- [测试策略](test-strategy.zh-CN.md)
- [运维运行手册](operations/runbook.zh-CN.md)
- [在线 RDPWindows BEADS 路径](live-rdpwindows-beads.zh-CN.md)

## 主要构件

- 安装器：[scripts/Install-OpenClawStack.ps1](../scripts/Install-OpenClawStack.ps1)
- TinyKVM 宿主安装器：[scripts/Install-OpenClawTinyKvmHost.sh](../scripts/Install-OpenClawTinyKvmHost.sh)
- TinyKVM 宿主加固：[scripts/Apply-OpenClawSystemdHardening.sh](../scripts/Apply-OpenClawSystemdHardening.sh)
- TinyKVM 工具安装器：[scripts/Install-TinyKvmTooling.sh](../scripts/Install-TinyKvmTooling.sh)
- 便携式安装包：[installer/README.md](../installer/README.md)
- 验证包装器：[scripts/Invoke-OpenClawDeploymentValidation.ps1](../scripts/Invoke-OpenClawDeploymentValidation.ps1)
- Compose 栈：[compose.yaml](../compose.yaml)
- 环境模板：[.env.example](../.env.example)
- VM 验证脚手架：[vm/README.md](../vm/README.md)

## 执行模型

- Windows 负责 PowerShell 运维入口及可选前置条件安装。
- Docker Desktop 通过 WSL2 后端提供容器运行时。
- Ollama 作为独立容器运行并承载本地模型。
- OpenClaw 在与上游兼容的网关容器中运行，并辅以 CLI 容器用于初始化和运维命令。
- TinyKVM 路径则改为让 OpenClaw 直接运行在 Linux 上，并显式使用 TinyKVM 工具处理 Linux ELF 执行。
