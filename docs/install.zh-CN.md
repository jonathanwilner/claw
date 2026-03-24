# 安装指南

[English](install.md)

## 支持路径

标准路径如下：

1. Windows 11 宿主机
2. 已启用 WSL2
3. 使用 WSL2 后端的 Docker Desktop
4. PowerShell 驱动的安装器
5. Docker 化的 `ollama` + `openclaw-gateway`

## 前置条件

- 已启用虚拟化的 Windows 11
- 如果希望脚本代你安装 WSL2 或 Docker Desktop，需要管理员权限 PowerShell
- 在最终部署步骤之前，Docker Desktop 需要已经运行
- 为选定的 Ollama 模型预留足够磁盘空间

## 首次安装

在项目根目录下的 Windows PowerShell 中运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-OpenClawStack.ps1 `
  -InstallWsl `
  -InstallDockerDesktop `
  -Model 'glm-4.7-flash'
```

如果 WSL2 和 Docker Desktop 已经安装：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-OpenClawStack.ps1 `
  -Model 'glm-4.7-flash'
```

若要在安装过程中包含腾讯微信插件：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-OpenClawStack.ps1 `
  -Model 'glm-4.7-flash' `
  -InstallWeixinPlugin
```

如果希望安装器停下来等待插件的二维码登录流程，增加 `-WeixinQrLogin`。

## 便携式 Bundle 路径

如果你希望获得一个可复制到另一台 Windows 机器上运行的包，请使用 [installer/README.md](../installer/README.md) 中的启动器。

该启动器会检测 `x64` 与 `arm64`，选择匹配的负载目录，然后转发到现有 PowerShell 安装器：

```powershell
powershell -ExecutionPolicy Bypass -File .\installer\Start-OpenClawPortableBundle.ps1 `
  -InstallWsl `
  -InstallDockerDesktop `
  -Model 'glm-4.7-flash'
```

## 安装器实际执行的内容

- 在请求 `-InstallWsl` 或 `-InstallDockerDesktop` 时，运行 [Install-OpenClawPrereqs.ps1](../scripts/Install-OpenClawPrereqs.ps1)
- 通过 `docker info` 验证 Docker 可访问性
- 创建 `state/openclaw-config`、`state/openclaw-workspace` 和 `state/ollama`
- 写入项目本地 `.env`
- 拉取配置的容器镜像
- 启动 `ollama` 容器
- 把配置的本地模型拉取到 Ollama
- 启动 OpenClaw 网关服务
- 针对 `http://127.0.0.1:11434` 运行官方非交互式 OpenClaw 初始化
- 可选安装 `@tencent-weixin/openclaw-weixin` 并启用 `openclaw-weixin` 插件
- 重启网关并运行部署验证，除非设置 `-SkipValidation`

## 架构说明

- `x64` Windows 使用常规 Docker Desktop 安装流程。
- `arm64` Windows 也支持，但 Docker Desktop 应视为 `仅限 WSL2` 且仍属 `Early Access`。
- 当系统自带 `wsl.exe` 仍是旧安装 stub 时，前置安装器可以旁加载微软官方 WSL MSI。

## 便携式 Bundle

如需在另一台机器上运行打包安装树，请使用 [installer/Start-OpenClawPortableBundle.ps1](../installer/Start-OpenClawPortableBundle.ps1)。

该启动器会：

- 检测 `x64` 或 `arm64`
- 选择对应的负载根目录
- 转发预置的 `wsl.msi` 和 `DockerDesktopInstaller.exe`
- 导入预置的 `images/*.tar` 镜像归档
- 恢复预置的 `ollama-models/ollama-models.tar.gz`
- 转发预置的 `npm/*.tgz` 微信插件 tarball
- 调用 [Install-OpenClawStack.ps1](../scripts/Install-OpenClawStack.ps1)
- 同时通过环境变量导出解析后的架构与负载根目录，供后续预置资源使用

## 验证

手动检查：

```powershell
docker compose ps
docker compose logs --tail=100 openclaw-gateway
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-OpenClawDeploymentValidation.ps1 `
  -OllamaUri 'http://127.0.0.1:11434/api/tags' `
  -OpenClawUri 'http://127.0.0.1:18789/healthz' `
  -WeixinMarkerPath '.\state\openclaw-config\openclaw-weixin-packaging.json' `
  -RequiredContainers openclaw-ollama,openclaw-gateway,openclaw-ollama-loopback
```

预期端点：

- Ollama：`http://127.0.0.1:11434/api/tags`
- OpenClaw 健康检查：`http://127.0.0.1:18789/healthz`

## 重置或重新配置

如果需要重建生成的 OpenClaw 配置和工作区状态：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-OpenClawStack.ps1 `
  -ResetConfig `
  -Model 'glm-4.7-flash'
```

## 升级

1. 修改 `.env` 中的镜像标签，或带新参数重新运行安装器。
2. 再次运行安装器。
3. 重新运行部署验证。

## 卸载

```powershell
docker compose down
Remove-Item -Recurse -Force .\state
Remove-Item -Force .\.env
```

如果 Docker Desktop 或 WSL2 只是为了该栈安装的，请用正常的 Windows 包管理方式单独卸载它们。
