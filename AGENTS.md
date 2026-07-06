# AGENTS.md

Guide for AI agents (and humans) working on this repository.

## Overview

`carrier-ims-module` is a **root module** (KernelSU / Magisk / APatch) that
persistently applies Pixel carrier/IMS `CarrierConfig` overrides via a
privileged app. It is a **fork** of the Shizuku-based app
[`ryfineZ/carrier-ims-for-pixel`](https://github.com/ryfineZ/carrier-ims-for-pixel).

> The original app source lives one directory up at `../app`, `../stub` when
> this repo is cloned inside the parent — use it as the **reference** for the
> carrier-config logic that was ported (it is NOT part of this repo).

### Why a fork
The original app must re-apply config on every boot / SIM swap because Shizuku
runs as shell UID and persistent overrides are gated on `FLAG_SYSTEM`
(`ShizukuProvider.kt:168`). This module fixes it with a `/system/priv-app/`
that holds `MODIFY_PHONE_STATE` → `overrideConfig(persistent=true)`.

## Build

```sh
./build-module.sh          # from the repo root
```

Prerequisites: **JDK 17+**, **Android SDK** with `platforms;android-36`
(`compileSdk=36`, `minSdk=33`). Produces `../carrier-ims-v<version>.zip`
(version read from `module.prop`).

The script: `./gradlew :privapp:assembleRelease` → copies the APK into
`system/priv-app/CarrierImsApplier/CarrierImsApplier.apk` → zips the module
root (excluding `privapp/build`, `.gradle`, `.git`).

## Module structure

| Path | Purpose |
|------|---------|
| `module.prop` | Module identity + `updateJson` (manager OTA). |
| `update.json` | OTA descriptor the manager reads for updates. |
| `customize.sh` | Multi-root installer (KernelSU/Magisk/APatch). |
| `service.sh` | `late_start`: seeds `config.json`, boot-safety broadcast. |
| `uninstall.sh` | Cleans `/data/adb/carrier_ims`. |
| `bin/apply.sh` | WebUI → base64-decode config.json + `am broadcast APPLY_CONFIG`. |
| `bin/read-config.sh` `bin/status.sh` | WebUI config/status reads. |
| `bin/captive-portal.sh` | Shell-only CN captive-portal fix/restore/query. |
| `system/priv-app/CarrierImsApplier/` | Built APK placed here by `build-module.sh`. |
| `system/etc/permissions/privapp-permissions-carrier_ims.xml` | Grants `MODIFY_PHONE_STATE` etc. |
| `privapp/` | Gradle subproject → `CarrierImsApplier.apk`. |
| `webroot/` | Committed WebUI (`index.html`, `app.js`, `style.css`). |

## Conventions

### config.json — `/data/adb/carrier_ims/config.json` (world-readable)

The module's single source of truth. Keyed by **slot index** (stable physical
position), **not** `subId` (unstable across SIM re-insert).

```json
{
  "enabled": true,
  "applyOnBoot": true,
  "applyOnSimChange": true,
  "slots": {
    "0": {
      "carrierName": "", "countryIso": "", "countryMccOverride": "",
      "volte": true, "vowifi": true, "vt": true, "vonr": true,
      "crossSim": true, "ut": true, "fiveGnr": true,
      "fiveGThresholds": true, "fiveGPlusIcon": true, "show4gForLte": false
    }
  }
}
```

### status.json — `/data/adb/carrier_ims/status.json`

Written by `Applier` after each apply:

```json
{ "lastApplyMillis": 0, "enabled": true,
  "slots": [ { "slotIndex": 0, "subId": 1, "applied": true, "imsRegistered": true } ] }
```

### Shell scripts

- Always start with `MODDIR=${0%/*}` to resolve the module dir; scripts run with
  BusyBox `ash` under all three roots.
- `bin/*.sh` are invoked from the WebUI as `sh $MODDIR/bin/<name>.sh`.

### Privileged app

- `overrideConfig` is a **hidden** method → reached by **reflection**
  (`Applier.invokeOverrideConfig`): try 3-arg `(int, PersistableBundle, boolean)`
  then 2-arg. Pass `persistent=true`; on failure fall back to `persistent=false`
  (boot/SIM-change re-apply covers the gap).
- IMS status (`createForSubscriptionId` / `isImsRegistered(int)`) is also hidden
  → reflected (`Applier`).
- The 13-toggle bundle is ported verbatim from the upstream `ImsModifier.buildBundle`
  into `privapp/.../ConfigBuilder.kt`.
- **slot → subId mapping**: at apply time enumerate
  `SubscriptionManager.activeSubscriptionInfoList`, map each `simSlotIndex` to
  its `subscriptionId`, then override for that subId.

## Release

1. Bump `module.prop` `version` + `versionCode`.
2. Bump `update.json` `version` / `versionCode` / `zipUrl` to match.
3. `./build-module.sh` → produces `carrier-ims-v<version>.zip`.
4. Tag `v<version>`, attach the zip to the GitHub release.
   The manager reads `update.json` (raw URL) and offers the update.

## Don'ts

- No commercial/ad/DoDoPay/business code (intentionally not carried over).
- No Zygisk — plain `/system` overlay + priv-app only.
- No in-WebUI update button — updates go through the root manager's OTA
  (`module.prop.updateJson`).
- Do **not** port the TikTok `setCarrierTestOverride`, APN editor, or
  `ImsResetter` paths — they need AIDL stubs and are one-shot operations, not
  persistence. They remain in the original Shizuku app.
