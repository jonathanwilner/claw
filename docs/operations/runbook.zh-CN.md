# 运维运行手册

[English](runbook.md)

## 启动

常规启动：

```powershell
docker compose up -d ollama openclaw-gateway ollama-loopback
```

完整重新初始化：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-OpenClawStack.ps1
```

## 关闭

```powershell
docker compose down
```

## 健康检查

检查运行中的服务：

```powershell
docker compose ps
```

检查健康端点：

```powershell
Invoke-WebRequest http://127.0.0.1:11434/api/tags -UseBasicParsing
Invoke-WebRequest http://127.0.0.1:18789/healthz -UseBasicParsing
```

运行打包验证套件：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-OpenClawDeploymentValidation.ps1 `
  -OllamaUri 'http://127.0.0.1:11434/api/tags' `
  -OpenClawUri 'http://127.0.0.1:18789/healthz' `
  -RequiredContainers openclaw-ollama,openclaw-gateway,openclaw-ollama-loopback
```

## 日志与诊断

```powershell
docker compose logs --tail=200 ollama
docker compose logs --tail=200 openclaw-gateway
docker compose logs --tail=200 ollama-loopback
```

如果 VM 验证失败，可通过 [vm/scripts/guest/Collect-Diagnostics.ps1](../../vm/scripts/guest/Collect-Diagnostics.ps1) 收集来宾诊断信息。

## 升级

1. 在 `.env` 中更新镜像标签或模型选择，或者用新参数重新运行安装器。
2. 再次运行 [scripts/Install-OpenClawStack.ps1](../../scripts/Install-OpenClawStack.ps1)。
3. 重新运行部署验证。

## 回滚

1. 恢复 `.env` 中之前的镜像标签。
2. 运行 `docker compose pull`。
3. 运行 `docker compose up -d`。

状态目录刻意保持持久化，因此回滚时通常不需要重新拉取模型，除非你主动删除 `state/`。

## 常见故障模式

- `docker info` 失败：Docker Desktop 已安装，但尚未启动或未完成初始化。
- `wsl.exe` 报告没有 version 2 发行版：WSL 已存在，但 Windows 宿主尚未处于受支持运行状态。
- OpenClaw 初始化无法找到 Ollama：检查 `ollama-loopback` 容器，并验证在 OpenClaw 命名空间中 `127.0.0.1:11434` 是否可达。
- 模型拉取很慢或超时：所选模型可能对本地磁盘、内存或网络条件要求过高。

## 恢复

如果生成的配置损坏，或需要重新生成选定模型：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-OpenClawStack.ps1 `
  -ResetConfig
```
