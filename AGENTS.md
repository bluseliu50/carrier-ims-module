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

## Documentation language

- **README.md** is **Chinese** (the default shown on GitHub).
- **README_EN.md** is the **English** version. The two link to each other.
- Keep them in sync when you change one.
- Do **not** mix English into `README.md` or Chinese into `README_EN.md`.
- Use **formal written register** in both READMEs — no colloquialisms, slang,
  or casual phrasing (e.g. avoid "塞一个", "那条路只认", "拔卡换卡"; write
  "放置一个", "仅允许", "插入或更换 SIM 卡"). Technical terms and code
  identifiers stay in English.

## Git conventions

- **Commit messages are always in English**, conventional-commits style
  (`feat:`, `fix:`, `docs:`, `ci:`, `chore:`, `refactor:`).
- **Single long-lived branch: `master`.** Push directly to `master`; there is
  no `develop` or release-staging branch. Large experiments may use a
  temporary feature branch, merged back and deleted.
- Tag releases as `v<version>` (e.g. `v1.0.0`) on `master`.
- Do not force-push to `master` — history is linear and fast-forward.

## Build

```sh
./build-module.sh          # from the repo root
```

Prerequisites: **JDK 21**, **Android SDK** with `platforms;android-36`
(`compileSdk=36`, `minSdk=33`). Produces `../carrier-ims-v<version>.zip`
(version read from `module.prop`).

The script: `./gradlew :privapp:assembleRelease` → copies the APK into
`system/priv-app/CarrierImsApplier/CarrierImsApplier.apk` → stages only the
runtime files into a temp dir → zips it (no `privapp/build`, `.gradle`,
`.git`, `README*`, `AGENTS.md` in the install zip).

## CI

`.github/workflows/build.yml` runs on push to `master`, on PRs to `master`,
on `v*` tags, and via `workflow_dispatch`. It:

1. Sets up JDK 21 + Android SDK (`platforms;android-36`, `build-tools;36.0.0`)
   by calling `sdkmanager` directly (the runner's `sdkmanager` is not on PATH;
   use `$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager`).
2. `./gradlew :privapp:assembleRelease`.
3. `./build-module.sh`.
4. Verifies the zip structure (all install-time files present, `module.prop`
   parses, `id` matches the required regex).
5. Uploads the module zip as an artifact.
6. On `v*` tags only: creates a GitHub Release with
   `carrier-ims-v<version>.zip` (the `update.json` OTA target).

## Module structure

| Path | Purpose |
|------|---------|
| `README.md` | Chinese README (default on GitHub). |
| `README_EN.md` | English README. |
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
| `.github/workflows/build.yml` | CI: build + verify + (on tags) release. |

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

### Privileged app — compile against the public SDK

The priv-app must compile against the **public** Android SDK (no hidden-API
stubs, no `android:privileged` manifest attr). All hidden APIs are reached by
**reflection** or literal string constants:

- `overrideConfig` is hidden → `Applier.invokeOverrideConfig` reflects the
  3-arg `(int, PersistableBundle, boolean)` then the 2-arg form. Pass
  `persistent=true`; on failure fall back to `persistent=false`
  (boot/SIM-change re-apply covers the gap).
- `TelephonyManager.createForSubscriptionId` / `isImsRegistered(int)` are
  hidden → reflected in `Applier`.
- `Intent.ACTION_SIM_STATE_CHANGED` and
  `TelephonyManager.ACTION_MULTI_SIM_CONFIG_CHANGED` are hidden → use the
  literal strings `"android.intent.action.SIM_STATE_CHANGED"` and
  `"android.telephony.action.MULTI_SIM_CONFIG_CHANGED"` in `BootReceiver` and
  the manifest.
- `android:privileged` is a hidden manifest attribute → **omit it**. Privileged
  status comes from being installed in `/system/priv-app/`, not the manifest.
- Kotlin 2.3.0 removed the `kotlinOptions` DSL → use
  `kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_21) } }`
  (see `privapp/build.gradle.kts`).
- No `const val` inside a class body — use plain `val`.

The 13-toggle bundle is ported verbatim from the upstream `ImsModifier.buildBundle`
into `privapp/.../ConfigBuilder.kt`.

**slot → subId mapping**: at apply time enumerate
`SubscriptionManager.activeSubscriptionInfoList`, map each `simSlotIndex` to
its `subscriptionId`, then override for that subId.

## Release

1. Bump `module.prop` `version` + `versionCode`.
2. Bump `update.json` `version` / `versionCode` / `zipUrl` to match.
3. Commit on `master`, then tag `v<version>` and push the tag — CI builds and
   creates the GitHub Release with `carrier-ims-v<version>.zip` attached.
   The manager reads `update.json` (raw URL) and offers the update.

## Don'ts

- No commercial/ad/DoDoPay/business code (intentionally not carried over).
- No Zygisk — plain `/system` overlay + priv-app only.
- No in-WebUI update button — updates go through the root manager's OTA
  (`module.prop.updateJson`).
- Do **not** port the TikTok `setCarrierTestOverride`, APN editor, or
  `ImsResetter` paths — they need AIDL stubs and are one-shot operations, not
  persistence. They remain in the original Shizuku app.
- Do **not** commit Chinese commit messages, and do **not** mix languages
  within a single README file.
