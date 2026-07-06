# Carrier IMS (Root)

一个给 Pixel 手机用的 root 模块（KernelSU / Magisk / APatch 通用），把运营商 / IMS 配置（VoLTE、VoWiFi、VoNR、视频通话、跨 SIM 通话、UT、5G NR、5G+ 图标等）持久化写入系统，重启、拔卡、换卡都不用再手动开一次。

本仓库是 [`ryfineZ/carrier-ims-for-pixel`](https://github.com/ryfineZ/carrier-ims-for-pixel)（基于 Shizuku 的原版 App）的 fork。原版每次开机或换卡都要重新执行一遍——因为 Shizuku 跑在 shell UID 下，而持久化配置那条路只认 `FLAG_SYSTEM`。本模块的解法是：在 `/system/priv-app/` 里塞一个特权 App，拿住 `MODIFY_PHONE_STATE` 权限，直接调用 `overrideConfig(persistent=true)`。

[English version](README_EN.md)

## 解决了什么

- **开机 / 拔卡 / 换卡不再重新执行**：配置按卡槽索引（slot index，物理位置稳定）保存，而不是按 `subId`（每次插拔都变）。写入即持久化，开机和换卡时还会自动补一次。
- **三端通用**：同一个 zip 在 KernelSU、Magisk、APatch 上都能装。
- **不用 Zygisk**：纯 `/system` 覆盖 + 特权 App，不依赖 ZygiskNext。
- **带 WebUI 控制台**：按卡槽开关各项功能、看状态、修国内 captive portal。
- **更新走管理器自带 OTA**（`module.prop` 里的 `updateJson`）。

## 安装

1. 去 [Releases](https://github.com/bluseliu50/carrier-ims-module/releases) 下载 `carrier-ims-v<版本号>.zip`。
2. 用你的 root 管理器（KernelSU / Magisk / APatch）刷入，重启。
3. 打开模块的 **WebUI**，按卡槽勾选功能，点 **应用**。

## 从源码构建

```sh
git clone https://github.com/bluseliu50/carrier-ims-module.git
cd carrier-ims-module
./build-module.sh      # 需要 JDK 21 和 Android SDK（platform 36）
```

产物：`carrier-ims-v<版本号>.zip`。

## 工作原理

```
config.json (/data/adb/carrier_ims/)   ← WebUI 通过 bin/apply.sh 写入
        │
        ▼
CarrierImsApplier（特权 App，持有 MODIFY_PHONE_STATE）
   • 开机 / SIM 状态变化 / WebUI 广播 → 触发 ApplierService
   • Applier：slot → 当前 subId → ConfigBuilder → overrideConfig(persistent=true)
   • 写入 status.json（最近一次应用时间、每个卡槽是否成功、IMS 是否注册）
```

持久化有兜底：万一某个 ROM 拒绝持久化写入，模块会退回非持久化，靠开机 + 换卡时自动重补，用户看到的效果一样。

## 配置说明

`config.json` / `status.json` 的字段和开发约定见 [`AGENTS.md`](AGENTS.md)。

## 许可证

继承上游项目的许可证（见 `LICENSE`）。
