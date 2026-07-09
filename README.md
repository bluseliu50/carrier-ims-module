# Carrier IMS (Root)

适用于 Pixel 手机的 root 模块（兼容 KernelSU / Magisk / APatch），可解锁并配置运营商 / IMS 功能（VoLTE、VoWiFi、VoNR、视频通话、跨 SIM 通话、UT、5G NR、5G+ 图标等）。开机、插入或更换 SIM 卡后自动重新应用，无需手动操作。

本仓库是 [`ryfineZ/carrier-ims-for-pixel`](https://github.com/ryfineZ/carrier-ims-for-pixel)（基于 Shizuku 的原版应用）的 fork。原版应用在每次开机或更换 SIM 卡后都需手动重新执行——原因在于 Shizuku 以 shell UID 运行，而 `overrideConfig` 的持久化覆盖路径仅允许 `FLAG_SYSTEM` 调用。本模块的解决方案：通过 `app_process` 以 root 身份运行，直接通过 `ServiceManager` 获取 binder 服务并调用 `overrideConfig`，同时以守护进程在开机和 SIM 卡变动时自动重新应用。

[English version](README_EN.md)

## 核心特性

- **开机与更换 SIM 卡后自动应用**：后台守护进程在开机后等待 SIM 就绪即自动应用配置，并持续轮询 SIM 状态变化，检测到拔卡 / 换卡后自动重新应用。
- **纯 root 实现**：无 `/system/priv-app`、无 privapp-permissions、无 `/system` 覆盖叠加，零 boot-loop 风险。
- **多 root 兼容**：同一 zip 可在 KernelSU、Magisk、APatch 上安装。
- **无需 Zygisk**：不依赖 ZygiskNext 或任何额外框架。
- **WebUI 控制台**：Material 设计风格，支持按卡槽逐项开关功能并查看 IMS 注册状态。
- **更新由 root 管理器内置 OTA 完成**（`module.prop` 中的 `updateJson`）。

> 本模块不设总开关：如需停用，使用 root 管理器自带的模块开关即可。

## 安装

1. 前往 [GitHub Actions](https://github.com/bluseliu50/carrier-ims-module/actions) 或 [Releases](https://github.com/bluseliu50/carrier-ims-module/releases) 下载模块 zip。
2. 在 root 管理器（KernelSU / Magisk / APatch）中刷入该 zip，随后重启设备。
3. 打开模块的 **WebUI**，按卡槽勾选所需功能，点击 **应用**。

## 从源码构建

```sh
git clone https://github.com/bluseliu50/carrier-ims-module.git
cd carrier-ims-module
./build-module.sh      # 需要 JDK 21 与 Android SDK（platform 36、build-tools）
```

构建产物：`carrier-ims-v<版本号>.zip`。

也可直接通过 GitHub Actions CI 自动构建（推送至 `master` 即触发）。

## 工作原理

```
WebUI (app.js)
   │  base64(JSON) → bin/apply.sh → bin/apply-root.sh
   ▼
app_process / Applier  (uid 0, root)
   │  • 以 root 获取 binder 服务（carrier_config / isub / phone）
   │  • ISub.getSubId(slot) → 取得各卡槽当前 subId
   │  • buildBundle() → 构建运营商配置（移植自原版 ImsModifier）
   │  • overrideConfig(subId, bundle, persistent=false)
   │  • ITelephony.isImsRegistered(subId) → 读取 IMS 注册状态
   ▼
status.json (/data/adb/carrier_ims/)
   • 最近应用时间、各卡槽是否成功、IMS 注册状态

service.sh (守护进程)
   • 开机后等待 SIM 就绪 → 自动应用
   • 每 15 秒轮询 SIM 状态 → 检测到变动后重新应用
```

**为何使用非持久化覆盖？** `overrideConfig(persistent=true)` 受 `CarrierConfigLoader` 内部检查限制，在 system_server 之外不可靠。本模块改用 `persistent=false`（内存覆盖），并以 `service.sh` 守护进程在开机和 SIM 卡变动时自动重新应用——用户可感知的效果与持久化完全一致，且与原版 Shizuku 应用的工作方式相同。

## 配置说明

`config.json` 与 `status.json` 的字段定义及开发约定详见 [`AGENTS.md`](AGENTS.md)。

## 许可证

继承上游项目的许可证（见 `LICENSE`）。
