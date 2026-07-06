# Carrier IMS (Root)

A **standalone root module** (KernelSU / Magisk / APatch) that persistently
applies Pixel carrier/IMS `CarrierConfig` overrides — VoLTE, VoWiFi, VoNR,
video calling, cross-SIM, UT, 5G NR / 5G+ icon — so they survive reboot and
SIM swap **without re-applying every time**.

This is a fork of [`ryfineZ/carrier-ims-for-pixel`](https://github.com/ryfineZ/carrier-ims-for-pixel)
(the Shizuku-based app). The original app re-applied config on every boot/SIM
change because Shizuku runs as a shell UID and the persistent-override path is
gated on `FLAG_SYSTEM`. This module solves it by shipping a **privileged app**
in `/system/priv-app/` that holds `MODIFY_PHONE_STATE` and calls
`overrideConfig(persistent=true)`.

## Why this exists

- **Solves 每次启动/拔卡换卡重新执行** — config is keyed by **slot index**
  (stable physical position), not the unstable `subId`, and applied
  persistently + re-applied on boot and SIM change.
- **Multi-root** — one zip works on KernelSU, Magisk and APatch.
- **Non-Zygisk** — plain `/system` overlay + priv-app.
- **WebUI console** — per-slot toggles, status, and a captive-portal CN fix.
- Updates ship through your root manager's built-in OTA (`module.prop.updateJson`).

## Install

1. Download `carrier-ims-v<version>.zip` from [Releases](https://github.com/bluseliu50/carrier-ims-module/releases).
2. Install via your root manager (KernelSU / Magisk / APatch) → reboot.
3. Open the module **WebUI** to configure toggles per SIM slot and press **Apply**.

## Build from source

```sh
git clone https://github.com/bluseliu50/carrier-ims-module.git
cd carrier-ims-module
./build-module.sh          # needs JDK 17+ and Android SDK platform 36
```

Produces `carrier-ims-v<version>.zip`.

## How it works

```
config.json (/data/adb/carrier_ims/)   ← written by WebUI (bin/apply.sh)
        │
        ▼
CarrierImsApplier (priv-app, holds MODIFY_PHONE_STATE)
   • BootReceiver / SIM_STATE_CHANGED / WebUI broadcast → ApplierService
   • Applier: slot → active subId → ConfigBuilder → overrideConfig(persistent=true)
   • writes status.json (last apply, per-slot applied + IMS-registered)
```

Persistence has a contingency fallback: if a ROM rejects persistent overrides,
the app applies non-persistent and the boot + SIM-change auto re-apply covers
the gap — the user-visible result is identical.

## Configuration

See [`AGENTS.md`](AGENTS.md) for the `config.json` / `status.json` schemas and
developer conventions.

## License

Inherits the upstream project's license (see `LICENSE`).
