# 微信集成

[English](weixin.md)

该打包路径支持来自 npm 的腾讯 OpenClaw 微信插件：

- 包名：`@tencent-weixin/openclaw-weixin`
- 本次更新验证的 npm 版本：`1.0.3`

该插件会在基础 OpenClaw 初始化完成后安装，并持久化到打包后的 OpenClaw 配置卷中。

## 在线安装

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-OpenClawStack.ps1 `
  -Model 'glm-4.7-flash' `
  -InstallWeixinPlugin
```

这会按默认 npm spec 从 npm 安装插件：

```text
@tencent-weixin/openclaw-weixin
```

## 离线安装

在有网络的机器上导出插件 tarball：

```bash
./installer/Export-OpenClawOfflinePayload.sh \
  --output-root /tmp/openclaw-offline-x64 \
  --weixin-plugin-npm-spec @tencent-weixin/openclaw-weixin
```

然后把它加入便携式 bundle：

```bash
./installer/Build-OpenClawPortableBundle.sh \
  --project-root /home/jonathan/src/claw \
  --output-root /tmp/openclaw-portable-bundle \
  --weixin-plugin-archive-x64 /tmp/openclaw-offline-x64/npm/tencent-weixin-openclaw-weixin-1.0.3.tgz
```

如果在 `installer/payload/<arch>/npm/` 下发现预置插件 tarball，便携式启动器会自动转发它。

## 二维码登录

腾讯插件的账号登录仍然必须是交互式，因为它要求用微信扫码授权：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-OpenClawStack.ps1 `
  -Model 'glm-4.7-flash' `
  -InstallWeixinPlugin `
  -WeixinQrLogin
```

也可以在之后单独触发登录：

```powershell
docker compose run --rm openclaw-cli channels login --channel openclaw-weixin
docker compose restart openclaw-gateway ollama-loopback
```

## 验证

打包层会在插件安装完成后写入一个标记文件：

```text
state/openclaw-config/openclaw-weixin-packaging.json
```

该文件证明打包集成路径已完成，但并不能证明二维码登录成功，因为二维码登录必须依赖真实且交互式的微信账号。

## 说明

- 重复执行 `openclaw channels login --channel openclaw-weixin` 可以增加更多微信账号
- 如果希望按“微信账号 + 发送者”隔离 AI 上下文，可执行 `openclaw config set agents.mode per-channel-per-peer`
- 本仓库通过 npm 或预置 tarball 安装插件，不内置腾讯插件源码
