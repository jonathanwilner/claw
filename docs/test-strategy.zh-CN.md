# 测试策略

[English](test-strategy.md)

## 目标

验证策略分为四层：

- Linux 上的 TinyKVM 宿主验证
- 快速 PowerShell 逻辑检查
- Windows 宿主级部署冒烟测试
- 一次性 Windows 11 Hyper-V 虚拟机中的完整打包验证

## TinyKVM 宿主层

对于 Linux / TinyKVM 路径，运行：

```bash
./scripts/Validate-OpenClawTinyKvmHost.sh
```

它会检查：

- `/dev/kvm` 是否存在以及是否可访问
- TinyKVM runner 二进制是否已安装
- Ollama 是否可达
- OpenClaw 网关状态与健康检查
- 当前 OpenClaw 配置是否能看到模型

## 本地测试层

[tests/OpenClaw.DeploymentValidation.Tests.ps1](../tests/OpenClaw.DeploymentValidation.Tests.ps1) 中的 Pester 套件会验证可复用的验证辅助逻辑：

- 统一化的检查对象
- `wsl.exe -l -v` 输出解析
- 部署汇总生成
- 微信插件 tarball 预置与打包标记逻辑

这些是最快的测试，不需要运行中的 Docker 栈。

## 宿主冒烟层

[scripts/Invoke-OpenClawDeploymentValidation.ps1](../scripts/Invoke-OpenClawDeploymentValidation.ps1) 包装器会检查：

- PowerShell 运行时可用性
- WSL2 可见性
- Docker CLI 与 daemon 健康状态
- 必需容器是否运行
- Ollama 与 OpenClaw HTTP 可达性
- 可选的微信打包标记是否存在

推荐命令：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-OpenClawDeploymentValidation.ps1 `
  -OllamaUri 'http://127.0.0.1:11434/api/tags' `
  -OpenClawUri 'http://127.0.0.1:18789/healthz' `
  -WeixinMarkerPath '.\state\openclaw-config\openclaw-weixin-packaging.json' `
  -RequiredContainers openclaw-ollama,openclaw-gateway,openclaw-ollama-loopback
```

## VM 验证层

[vm/README.md](../vm/README.md) 下的 Hyper-V/Packer 脚手架是发布级别的打包检查：

- 创建 Windows 11 来宾
- 安装或验证 Windows 前置条件
- 安装 Docker Desktop
- 预置打包后的仓库负载
- 在来宾内运行 [scripts/Install-OpenClawStack.ps1](../scripts/Install-OpenClawStack.ps1)
- 确认来宾内的 WSL2、Docker Desktop 与 OpenClaw 健康状态
- 如果启用微信，则验证插件安装标记，并把二维码登录作为仅发布阶段执行的人工检查

这是最接近真实用户首次安装的路径。

## CI Gate

[.github/workflows/vm-validation.yml](../.github/workflows/vm-validation.yml) 工作流刻意只做语法级检查：

- `packer init`
- `packer fmt -check`
- `packer validate`
- VM 脚本的 PowerShell 解析检查

它不会尝试嵌套虚拟化，也不会真正构建 Hyper-V 虚拟机。

## 发布 Gate

在把改动视为可发布之前：

- 应在带 PowerShell 与 Pester 的 Windows 机器上通过 Pester 验证
- 安装后应通过本地宿主冒烟验证
- 在真实 Windows 宿主并预置安装器的条件下，Hyper-V/Packer 流程应能完整跑通
