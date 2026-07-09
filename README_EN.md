# Carrier IMS (Root)

A root module for Pixel phones (works on KernelSU / Magisk / APatch) that
unlocks and configures carrier / IMS features (VoLTE, VoWiFi, VoNR, video
calling, cross-SIM calling, UT, 5G NR, 5G+ icon, etc.). Re-applies
automatically on boot, SIM removal and SIM swaps — no manual action needed.

This repo is a fork of [`ryfineZ/carrier-ims-for-pixel`](https://github.com/ryfineZ/carrier-ims-for-pixel)
(the Shizuku-based original app). The original had to be re-executed on every
boot / SIM change — Shizuku runs as a shell UID and the `overrideConfig`
persistent-override path only accepts `FLAG_SYSTEM` callers. This module's
fix: run an `app_process` program as root, acquire binder services directly
via `ServiceManager`, call `overrideConfig`, and re-apply automatically via
a background daemon on boot and SIM changes.

[中文版本](README.md)

## What it solves

- **Auto-apply on boot and SIM swap** — a background daemon waits for SIM
  readiness after boot and applies config automatically; it continuously polls
  SIM state and re-applies when a SIM change (removal / swap) is detected.
- **Pure-root** — no `/system/priv-app`, no privapp-permissions, no `/system`
  overlay. Zero boot-loop risk.
- **Multi-root** — the same zip installs on KernelSU, Magisk and APatch.
- **No Zygisk** — no ZygiskNext or any additional framework dependency.
- **WebUI console** — Material-styled, per-slot toggles and IMS status.
- **Updates via your root manager's built-in OTA** (`module.prop.updateJson`).

> The module has no master switch — to disable it, use your root manager's
> built-in module toggle.

## Install

1. Download the module zip from
   [GitHub Actions](https://github.com/bluseliu50/carrier-ims-module/actions)
   or [Releases](https://github.com/bluseliu50/carrier-ims-module/releases).
2. Flash it with your root manager (KernelSU / Magisk / APatch), reboot.
3. Open the module's **WebUI**, pick toggles per slot, hit **Apply**.

## Build from source

```sh
git clone https://github.com/bluseliu50/carrier-ims-module.git
cd carrier-ims-module
./build-module.sh      # needs JDK 21 and Android SDK (platform 36, build-tools)
```

Produces `carrier-ims-v<version>.zip`.

GitHub Actions CI also builds automatically on every push to `master`.

## How it works

```
WebUI (app.js)
   |  base64(JSON) → bin/apply.sh → bin/apply-root.sh
   v
app_process / Applier  (uid 0, root)
   |  • acquires binder services as root (carrier_config / isub / phone)
   |  • ISub.getSubId(slot) → resolve each slot's current subId
   |  • buildBundle() → build carrier config (ported from original ImsModifier)
   |  • overrideConfig(subId, bundle, persistent=false)
   |  • ITelephony.isImsRegistered(subId) → read IMS registration status
   v
status.json (/data/adb/carrier_ims/)
   • last apply time, per-slot success, IMS registered

service.sh (daemon)
   • waits for SIM ready after boot → auto-apply
   • polls SIM state every 15s → re-applies on change detected
```

**Why non-persistent overrides?** `overrideConfig(persistent=true)` is gated
by `CarrierConfigLoader`'s internal checks and doesn't reliably work outside
`system_server`. This module uses `persistent=false` (in-memory override)
with a `service.sh` daemon that re-applies on boot and SIM changes — the
user-visible result is identical to persistent, and matches how the original
Shizuku app works.

## Configuration

See [`AGENTS.md`](AGENTS.md) for the `config.json` / `status.json` schemas
and developer conventions.

## License

Inherits the upstream project's license (see `LICENSE`).
