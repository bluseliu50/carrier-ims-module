# Carrier IMS (Root)

A root module for Pixel phones (works on KernelSU / Magisk / APatch) that
persists carrier / IMS configuration (VoLTE, VoWiFi, VoNR, video calling,
cross-SIM calling, UT, 5G NR, 5G+ icon, etc.) into the system — so it survives
reboots, SIM removal and SIM swaps without re-applying every time.

This repo is a fork of [`ryfineZ/carrier-ims-for-pixel`](https://github.com/ryfineZ/carrier-ims-for-pixel)
(the Shizuku-based original app). The original had to be re-executed on every
boot / SIM change — Shizuku runs as a shell UID and the persistent-override
path only accepts `FLAG_SYSTEM` callers. This module's fix: ship a privileged
app in `/system/priv-app/` that holds `MODIFY_PHONE_STATE` and calls
`overrideConfig(persistent=true)`.

[中文版本](README.md)

## What it solves

- **No more re-applying on boot / SIM swap** — config is keyed by slot index
  (stable physical position), not `subId` (which changes on every re-insert).
  Writes are persistent, and a re-apply fires on boot and SIM change.
- **Multi-root** — the same zip installs on KernelSU, Magisk and APatch.
- **No Zygisk** — plain `/system` overlay + privileged app, no ZygiskNext
  dependency.
- **WebUI console** — per-slot toggles, status, and a captive-portal CN fix.
- **Updates via your root manager's built-in OTA** (`module.prop.updateJson`).

## Install

1. Download `carrier-ims-v<version>.zip` from
   [Releases](https://github.com/bluseliu50/carrier-ims-module/releases).
2. Flash it with your root manager (KernelSU / Magisk / APatch), reboot.
3. Open the module's **WebUI**, pick toggles per slot, hit **Apply**.

## Build from source

```sh
git clone https://github.com/bluseliu50/carrier-ims-module.git
cd carrier-ims-module
./build-module.sh      # needs JDK 21 and Android SDK (platform 36)
```

Produces `carrier-ims-v<version>.zip`.

## How it works

```
config.json (/data/adb/carrier_ims/)   ← written by WebUI via bin/apply.sh
        │
        ▼
CarrierImsApplier (privileged app, holds MODIFY_PHONE_STATE)
   • boot / SIM state change / WebUI broadcast → ApplierService
   • Applier: slot → current subId → ConfigBuilder → overrideConfig(persistent=true)
   • writes status.json (last apply time, per-slot success, IMS registered)
```

Persistence has a fallback: if a ROM rejects persistent writes, the module
falls back to non-persistent and the boot + SIM-change auto re-apply covers
the gap — the user-visible result is the same.

## Configuration

See [`AGENTS.md`](AGENTS.md) for the `config.json` / `status.json` schemas
and developer conventions.

## License

Inherits the upstream project's license (see `LICENSE`).
