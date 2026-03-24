# 架构

[English](architecture.md)

## BEADS 布局

该打包路径采用 BEADS 风格拆分：

- Bootstrap：通过 PowerShell 验证或安装 Windows、WSL2 与 Docker Desktop 前置条件
- Environment：在 `state/` 下创建可预测的 `.env` 文件和持久化目录
- Artifacts：使用上游 OpenClaw 与 Ollama 镜像，而不内置 OpenClaw 源码
- Deploy：拉取配置的模型，运行 `openclaw onboard --non-interactive`，并启动网关
- Smoke test：验证 Docker、WSL2、Ollama 和 OpenClaw 健康端点

## 边界模型

### Windows 宿主机

- 运行主要运维入口 [scripts/Install-OpenClawStack.ps1](../scripts/Install-OpenClawStack.ps1) 与 [scripts/Invoke-OpenClawDeploymentValidation.ps1](../scripts/Invoke-OpenClawDeploymentValidation.ps1)
- 可选通过 `wsl.exe` 与 `winget` 安装 WSL2 和 Docker Desktop
- 持有项目目录与 `state/` 绑定挂载
- 在 VM 验证阶段负责 Hyper-V 与 Packer

### WSL2

- 作为 Windows 上 Docker Desktop 的受支持后端
- 只是宿主前置条件和运行时基座，而不是本项目直接安装 OpenClaw 的地方
- 因为上游 Windows 指南以 WSL2 为优先，所以部署检查会验证它

### Docker 容器

- `ollama`：本地模型运行时，端口 `11434`
- `openclaw-gateway`：主 OpenClaw 网关，暴露 `18789` 与 `18790`
- `openclaw-cli`：用于初始化和后续运维命令的 CLI 容器
- `ollama-loopback`：本地转发器，让 `127.0.0.1:11434` 在网关网络命名空间内可用，从而无需修改上游 Ollama 初始化流程
- `@tencent-weixin/openclaw-weixin`：通过 OpenClaw CLI 容器安装的可选腾讯插件

## 数据与配置流

- `.env` 控制镜像标签、端口、时区、模型选择和绑定挂载路径
- `state/openclaw-config` 挂载到 `/home/node/.openclaw`
- `state/openclaw-workspace` 挂载到 `/home/node/.openclaw/workspace`
- `state/ollama` 挂载到 `/root/.ollama`
- 安装器先拉取模型，再使用 OpenClaw 初始化流程对接本地 Ollama
- 如果启用微信集成，安装器会再从 npm 或预置 tarball 安装腾讯插件，并将元数据写入 `state/openclaw-config/openclaw-weixin-packaging.json`

## 网络流

- Windows 宿主通过 `http://127.0.0.1:11434` 访问 Ollama
- Windows 宿主通过 `http://127.0.0.1:18789/healthz` 访问 OpenClaw 健康检查
- 在 OpenClaw 命名空间内，`ollama-loopback` 监听 `127.0.0.1:11434` 并转发到 `ollama`
- OpenClaw CLI 容器共享网关网络命名空间，因此初始化和后续 CLI 操作看到的是与网关一致的 loopback 端点

## 打包选择

该栈刻意尽量贴近当前上游 OpenClaw 的 Docker 模式。主要定制点是 Ollama loopback sidecar，其存在仅仅是为了在多容器打包部署中保留 OpenClaw 原生 Ollama 集成和工具调用行为。

## TinyKVM 优化拓扑

面向 TinyKVM 的路径刻意不同：

- OpenClaw 直接运行在 Linux 宿主机上，而不是打包网关容器内
- Ollama 仍可本地运行，包括继续使用现有 [compose.yaml](../compose.yaml) 中的 `ollama` 服务
- 该路径关闭 OpenClaw 沙箱模式，因为当前打包接口仍暴露的是 Docker 沙箱设置，而不是原生 TinyKVM 后端
- 宿主网关通过 user-systemd 覆盖单独加固，而不是假设 TinyKVM 本身就保护了控制平面
- TinyKVM 作为宿主工具安装，并通过 [tinykvm-runner/](../tinykvm-runner) 构建出的本地包装器调用

这是当前最干净的 TinyKVM 适配方式，因为它避免把旧的 Docker 网关边界和 Linux/KVM 原生执行模型强行叠在一起。

与此拆分相关的安全 reasoning 见 [tinykvm-security-architecture.zh-CN.md](tinykvm-security-architecture.zh-CN.md)。

## 架构感知的前置条件

打包层现在把前置条件安装单独拆出来：

- [Install-OpenClawPrereqs.ps1](../scripts/Install-OpenClawPrereqs.ps1) 负责 WSL 与 Docker Desktop
- [Start-OpenClawPortableBundle.ps1](../installer/Start-OpenClawPortableBundle.ps1) 在运行时选择 `x64` 或 `arm64` 负载
- [Build-OpenClawPortableBundle.sh](../installer/Build-OpenClawPortableBundle.sh) 构建可分发的 bundle 目录树

这种分离很重要，因为 Windows on Arm 不只是 CPU 架构变化，它还改变了 Docker Desktop 后端约束，因此应与对应架构的前置安装资源一起打包。

[installer/README.md](../installer/README.md) 下的便携式安装脚手架与这一模型并存。它在启动时做架构识别，因此单个 bundle 就能把 `x64` 和 `arm64` 机器路由到正确的负载目录，而不必改变 VM 验证路径。
