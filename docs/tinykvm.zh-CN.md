# TinyKVM 指南

[English](tinykvm.md)

## 有哪些变化

本仓库现在包含一条面向 Linux 的路径，用于让 OpenClaw 与 TinyKVM 并行工作。

这条路径刻意不同于旧的 Windows / WSL2 / Docker Desktop 打包方式：

- TinyKVM 需要通过 `/dev/kvm` 访问 Linux KVM
- 当前 `openclaw` 包在发布的配置模式里仍然暴露的是 Docker 风格沙箱设置
- 因此，今天最现实的 TinyKVM 适配方式是 `OpenClaw 网关运行在宿主机` + `TinyKVM 工具运行在同一台 Linux 机器`

换句话说：当当前包并未提供原生 TinyKVM 沙箱后端时，本仓库不会假装它已经存在。

## 推荐拓扑

- OpenClaw 网关直接运行在 Linux 宿主机上
- Ollama 仍本地运行，可复用现有 [compose.yaml](../compose.yaml) 中的 `ollama` 服务
- OpenClaw 沙箱模式设为 `off`，避免在 TinyKVM 工作流外再叠一层 Docker 沙箱
- 对 Linux ELF 工作负载，显式通过安装后的 `openclaw-tinykvm-run` 包装器使用 TinyKVM

如果你的目标是“在真正有帮助的地方使用 TinyKVM”，而不是维持旧的 Docker 化网关形态，这是当前最干净的边界模型。

安全架构说明请见 [tinykvm-security-architecture.zh-CN.md](tinykvm-security-architecture.zh-CN.md)。

## 脚本

- 宿主初始化：[Install-OpenClawTinyKvmHost.sh](../scripts/Install-OpenClawTinyKvmHost.sh)
- 宿主服务加固：[Apply-OpenClawSystemdHardening.sh](../scripts/Apply-OpenClawSystemdHardening.sh)
- TinyKVM 工具编译与安装：[Install-TinyKvmTooling.sh](../scripts/Install-TinyKvmTooling.sh)
- 验证：[Validate-OpenClawTinyKvmHost.sh](../scripts/Validate-OpenClawTinyKvmHost.sh)
- TinyKVM runner 包装器：[openclaw-tinykvm-run.sh](../scripts/openclaw-tinykvm-run.sh)
- Runner 源码：[openclaw_tinykvm_runner.cpp](../tinykvm-runner/openclaw_tinykvm_runner.cpp)

## 快速开始

构建并安装 TinyKVM runner：

```bash
./scripts/Install-TinyKvmTooling.sh
```

为 Linux 宿主路径安装并配置 OpenClaw：

```bash
./scripts/Install-OpenClawTinyKvmHost.sh
```

该安装器默认会对 OpenClaw 网关服务应用 user-systemd 加固覆盖。如果需要手动重新应用：

```bash
./scripts/Apply-OpenClawSystemdHardening.sh
```

验证最终状态：

```bash
./scripts/Validate-OpenClawTinyKvmHost.sh
```

在 TinyKVM 下运行一个 Linux ELF：

```bash
openclaw-tinykvm-run ./my-program
```

## 行为说明

- 如果系统中缺少 `openclaw`，`Install-OpenClawTinyKvmHost.sh` 会通过当前官方安装器安装它。
- 如果 `OLLAMA_BASE_URL` 已可访问，安装器会复用现有 Ollama，而不是启动 Docker `ollama` 服务。
- 它通过 `openclaw config set ...` 配置，而不是直接写入猜测的 JSON。
- 它会配置 `gateway.mode=local`、`gateway.bind=loopback`、基于 token 的网关认证、Ollama 作为模型提供方，以及 `agents.defaults.sandbox.mode=off`。
- 它会对宿主网关应用 Linux user-systemd 加固，因此 TinyKVM 不是路径里唯一的安全控制。
- TinyKVM runner 用于直接运行 Linux 二进制，而不是自动替换 OpenClaw 内置 Docker 沙箱。

## 限制

- OpenClaw 包支持仍然以 Docker 沙箱设置为中心。
- TinyKVM runner 当前针对 Linux ELF 程序，这正是 TinyKVM 用户态仿真模型的正确匹配。
- 在非 FHS 系统上，可能需要设置 `OPENCLAW_TINYKVM_DYNAMIC_LOADER=/path/to/ld-linux-...` 和 `OPENCLAW_TINYKVM_EXTRA_READ_PREFIXES=/nix/store`，以便 runner 能访问宿主动态加载器和共享库。
- 旧的 Windows 打包器仍保留在仓库中，但如果目标是 TinyKVM，它不是首选路径。
