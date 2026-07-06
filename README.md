# Carrier IMS (Root)

适用于 Pixel 手机的 root 模块（兼容 KernelSU / Magisk / APatch），可将运营商 / IMS 配置（VoLTE、VoWiFi、VoNR、视频通话、跨 SIM 通话、UT、5G NR、5G+ 图标等）持久化写入系统。重启、插入或更换 SIM 卡后，配置依然生效，无需手动重复应用。

本仓库是 [`ryfineZ/carrier-ims-for-pixel`](https://github.com/ryfineZ/carrier-ims-for-pixel)（基于 Shizuku 的原版应用）的 fork。原版应用在每次开机或更换 SIM 卡后都需重新执行——原因在于 Shizuku 以 shell UID 运行，而持久化覆盖路径仅允许 `FLAG_SYSTEM` 调用。本模块的解决方案：在 `/system/priv-app/` 中放置一个特权应用，持有 `MODIFY_PHONE_STATE` 权限，直接调用 `overrideConfig(persistent=true)`。

[English version](README_EN.md)

## 核心特性

- **开机与更换 SIM 卡后无需重新应用**：配置以卡槽索引（slot index，物理位置稳定）为键存储，而非 `subId`（每次插拔均会变化）。写入即为持久化，并在开机和 SIM 卡变动时自动重新应用。
- **多 root 兼容**：同一 zip 可在 KernelSU、Magisk、APatch 上安装。
- **无需 Zygisk**：仅采用 `/system` 覆盖叠加与特权应用，不依赖 ZygiskNext。
- **WebUI 控制台**：Material 设计风格，支持按卡槽逐项开关功能并查看 IMS 状态。
- **更新由 root 管理器内置 OTA 完成**（`module.prop` 中的 `updateJson`）。

> 本模块不设总开关：如需停用，使用 root 管理器自带的模块开关即可。

## 安装

1. 前往 [Releases](https://github.com/bluseliu50/carrier-ims-module/releases) 下载 `carrier-ims-v<版本号>.zip`。
2. 在 root 管理器（KernelSU / Magisk / APatch）中刷入该 zip，随后重启设备。
3. 打开模块的 **WebUI**，按卡槽勾选所需功能，点击 **应用**。

## 从源码构建

```sh
git clone https://github.com/bluseliu50/carrier-ims-module.git
cd carrier-ims-module
./build-module.sh      # 需要 JDK 21 与 Android SDK（platform 36）
```

构建产物：`carrier-ims-v<版本号>.zip`。

## 工作原理

```
config.json (/data/adb/carrier_ims/)   ← WebUI 通过 bin/apply.sh 写入
        │
        ▼
CarrierImsApplier（特权应用，持有 MODIFY_PHONE_STATE）
   • 开机 / SIM 状态变化 / WebUI 广播 → 直接调用 Applier（无前台服务）
   • Applier：slot → 当前 subId → ConfigBuilder → overrideConfig(persistent=true)
   • 写入 status.json（最近应用时间、各卡槽是否成功、IMS 注册状态）
```

持久化机制具备兜底策略：若特定 ROM 拒绝持久化写入，模块将回退至非持久化模式，并通过开机与 SIM 卡变动时的自动重新应用弥补差异，用户可感知的效果保持一致。

## 配置说明

`config.json` 与 `status.json` 的字段定义及开发约定详见 [`AGENTS.md`](AGENTS.md)。

## 许可证

继承上游项目的许可证（见 `LICENSE`）。
