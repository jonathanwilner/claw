# 便携式安装包

[English](README.md)

本目录是一个可复用 Windows 安装包的脚手架，可复制到另一台机器上并在本地运行。

## 布局

- `Build-OpenClawPortableBundle.sh`：在当前宿主上构建便携式 bundle 目录树
- `build_portable_bundle.py`：跨平台 bundle 构建实现
- `Export-OpenClawOfflinePayload.sh`：导出 Docker 镜像归档与可选 Ollama 模型负载
- `Start-OpenClawPortableBundle.ps1`：bundle 入口
- `Test-OpenClawPortableBundle.ps1`：在 bundle 上下文中运行打包验证
- `BundleManifest.json`：bundle 元数据和预留负载根目录描述
- `payload/x64/`：x64 专用资源预置目录
- `payload/arm64/`：arm64 专用资源预置目录

## 工作方式

bundle 启动器会：

1. 在运行时检测宿主架构
2. 为 `x64` 或 `arm64` 选择对应负载根目录
3. 定位一个可运行的 OpenClaw 项目树
4. 从负载根目录提供匹配架构的 WSL 与 Docker 安装器
5. 转发到 `scripts/Install-OpenClawStack.ps1`，由它复用共享前置安装路径

这种设计让便携式 bundle 保持轻量，同时又给打包路径提供了按架构分流的入口。

当预置负载存在时，bundle 也可以以近似离线方式运行：

- `images/*.tar`：Docker 镜像归档
- `ollama-models/ollama-models.tar.gz`：预加载 Ollama 模型库
- `npm/*.tgz`：预置插件 tarball，例如 `@tencent-weixin/openclaw-weixin`
- `wsl.msi`：官方微软 WSL 安装包
- `DockerDesktopInstaller.exe`：Docker Desktop 安装器

## 当前范围

- 这是脚手架，不是最终发布工件
- 它不会修改 `vm/` 下的 VM 宿主自动化
- 它假设复制树中已经包含 OpenClaw 仓库内容，或者通过 `-ProjectRoot` 提供
- 对于 Windows on Arm，应把 Docker Desktop 视为 `仅限 WSL2` 且仍属 `Early Access`；Windows 容器不在此路径之内

## 构建一个 Bundle

在当前宿主上的本仓库内运行：

```bash
./installer/Build-OpenClawPortableBundle.sh \
  --project-root /home/jonathan/src/claw \
  --output-root /tmp/openclaw-portable-bundle
```

## 导出离线负载

在有 Docker 的源机器上，为某一架构创建离线负载根目录：

```bash
./installer/Export-OpenClawOfflinePayload.sh \
  --output-root /tmp/openclaw-offline-x64 \
  --openclaw-image openclaw/openclaw:latest \
  --ollama-image ollama/ollama:latest \
  --helper-image alpine/socat:1.8.0.3 \
  --weixin-plugin-npm-spec @tencent-weixin/openclaw-weixin \
  --model glm-4.7-flash \
  --ollama-models-dir /path/to/.ollama/models
```

然后把该负载根目录加入 bundle：

```bash
./installer/Build-OpenClawPortableBundle.sh \
  --project-root /home/jonathan/src/claw \
  --output-root /tmp/openclaw-portable-bundle \
  --docker-images-x64-root /tmp/openclaw-offline-x64/images \
  --ollama-model-archive-x64 /tmp/openclaw-offline-x64/ollama-models/ollama-models.tar.gz \
  --weixin-plugin-archive-x64 /tmp/openclaw-offline-x64/npm/tencent-weixin-openclaw-weixin-1.0.3.tgz \
  --wsl-x64 /path/to/wsl.x64.msi \
  --docker-x64 /path/to/DockerDesktopInstaller-x64.exe
```

如果还要一并预置前置安装器：

```bash
./installer/Build-OpenClawPortableBundle.sh \
  --project-root /home/jonathan/src/claw \
  --output-root /tmp/openclaw-portable-bundle \
  --wsl-x64 /path/to/wsl.x64.msi \
  --wsl-arm64 /path/to/wsl.arm64.msi \
  --docker-x64 /path/to/DockerDesktopInstaller-x64.exe \
  --docker-arm64 /path/to/DockerDesktopInstaller-arm64.exe \
  --zip
```

## 示例

```powershell
powershell -ExecutionPolicy Bypass -File .\installer\Start-OpenClawPortableBundle.ps1 `
  -InstallWsl `
  -InstallDockerDesktop `
  -InstallWeixinPlugin `
  -Model 'glm-4.7-flash'
```

如果负载根目录中已经包含当前架构对应的 `wsl.msi` 和 `DockerDesktopInstaller.exe`，启动器会自动把它们转发给共享前置安装器。

如果负载根目录中还包含 `images/*.tar` 和 `ollama-models/ollama-models.tar.gz`，安装器会导入 Docker 镜像、恢复本地 LLM 负载，然后运行正常 OpenClaw 验证流程。

## 测试 Bundle

安装完成后：

```powershell
powershell -ExecutionPolicy Bypass -File .\installer\Test-OpenClawPortableBundle.ps1
```

如果只想查看行为而不真正运行安装器：

```powershell
powershell -ExecutionPolicy Bypass -File .\installer\Start-OpenClawPortableBundle.ps1 -DryRun
```
