# Weixin Integration

This packaging supports Tencent's OpenClaw Weixin plugin from npm:

- package: `@tencent-weixin/openclaw-weixin`
- validated npm version during this update: `1.0.3`

The plugin is installed after the base OpenClaw onboarding step and is persisted under the packaged OpenClaw config volume.

## Install Online

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-OpenClawStack.ps1 `
  -Model 'glm-4.7-flash' `
  -InstallWeixinPlugin
```

That installs the plugin from npm with the default spec:

```text
@tencent-weixin/openclaw-weixin
```

## Install Offline

Export the plugin tarball on a connected machine:

```bash
./installer/Export-OpenClawOfflinePayload.sh \
  --output-root /tmp/openclaw-offline-x64 \
  --weixin-plugin-npm-spec @tencent-weixin/openclaw-weixin
```

Then add it to the portable bundle:

```bash
./installer/Build-OpenClawPortableBundle.sh \
  --project-root /home/jonathan/src/claw \
  --output-root /tmp/openclaw-portable-bundle \
  --weixin-plugin-archive-x64 /tmp/openclaw-offline-x64/npm/tencent-weixin-openclaw-weixin-1.0.3.tgz
```

The portable launcher forwards a staged plugin tarball automatically when it finds one under `installer/payload/<arch>/npm/`.

## QR Login

The Tencent plugin's account login remains interactive because it requires QR-code authorization from WeChat:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-OpenClawStack.ps1 `
  -Model 'glm-4.7-flash' `
  -InstallWeixinPlugin `
  -WeixinQrLogin
```

You can also trigger login later:

```powershell
docker compose run --rm openclaw-cli channels login --channel openclaw-weixin
docker compose restart openclaw-gateway ollama-loopback
```

## Validation

The packaging layer writes a marker file after plugin install:

```text
state/openclaw-config/openclaw-weixin-packaging.json
```

That validates the packaging integration path. It does not validate a live QR login, because QR login requires an interactive WeChat account.

## Notes

- repeated `openclaw channels login --channel openclaw-weixin` adds more WeChat accounts
- if you want isolation per WeChat account and sender, use `openclaw config set agents.mode per-channel-per-peer`
- this repo installs the plugin from npm or a staged tarball; it does not vendor the Tencent plugin source code
