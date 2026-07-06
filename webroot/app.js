// Carrier IMS WebUI — Material 3 styled, vanilla JS, no bundler.
// Uses the KernelSU WebUI API via ES module import:
//   import { exec, toast } from 'kernelsu'
// (the documented form; a global is NOT exposed).

import { exec, toast } from 'kernelsu';

// ---- feature definitions (defaults mirror Feature.kt) ----
const FEATURES = [
  { key: "volte",           label: "VoLTE",        sub: "高清通话" },
  { key: "vowifi",          label: "VoWiFi",       sub: "Wi-Fi 通话" },
  { key: "vt",              label: "视频通话",      sub: "ViLTE" },
  { key: "vonr",            label: "VoNR",         sub: "5G 语音（需 Android 14+）" },
  { key: "crossSim",        label: "跨 SIM 通话",   sub: "Cross-SIM Calling" },
  { key: "ut",              label: "UT 补充业务",   sub: "补充服务 over UT" },
  { key: "fiveGnr",         label: "5G NR",        sub: "启用 5G" },
  { key: "fiveGPlusIcon",   label: "5G+ 图标",      sub: "NR Advanced 图标" },
  { key: "fiveGThresholds", label: "5G 信号阈值",   sub: "信号强度分级" },
  { key: "show4gForLte",    label: "LTE 显示为 4G", sub: "状态栏图标", def: false },
  { key: "tiktokNetworkFix",label: "TikTok 修复",   sub: "自动应用 CN 国家码", def: false },
];

const MODID = "carrier_ims";
const MODDIR = "/data/adb/modules/" + MODID;

let state = { slots: {} };
let activeSlot = 0;

// ---- base64 (UTF-8 safe) ----
function b64encode(str) {
  const bytes = new TextEncoder().encode(str);
  let bin = "";
  bytes.forEach((b) => (bin += String.fromCharCode(b)));
  return btoa(bin);
}

// ---- config helpers ----
function ensureSlot(slot) {
  if (!state.slots[slot]) {
    const s = {};
    for (const f of FEATURES) s[f.key] = f.def !== undefined ? f.def : true;
    state.slots[slot] = s;
  }
}

function loadLocal() {
  try {
    const s = localStorage.getItem("carrierims_state");
    if (s) state = Object.assign({ slots: {} }, JSON.parse(s));
  } catch (_) {}
}
function persistLocal() {
  try { localStorage.setItem("carrierims_state", JSON.stringify(state)); } catch (_) {}
}

// ---- device config load ----
async function loadConfig() {
  try {
    const { stdout } = await exec(`sh ${MODDIR}/bin/read-config.sh`);
    if (stdout) {
      const cfg = JSON.parse(stdout.trim());
      if (cfg && cfg.slots) state.slots = cfg.slots;
    }
  } catch (_) {}
  renderAll();
}

// ---- render ----
function renderTabs() {
  const host = document.getElementById("slotTabs");
  host.innerHTML = "";
  [0, 1].forEach((slot) => {
    const b = document.createElement("button");
    b.className = "seg" + (slot === activeSlot ? " active" : "");
    b.innerHTML = `<span class="dot"></span>卡槽 ${slot}`;
    b.addEventListener("click", () => {
      collectCurrent();
      activeSlot = slot;
      renderTabs();
      renderFeatures();
    });
    host.appendChild(b);
  });
}

function renderFeatures() {
  ensureSlot(activeSlot);
  const slot = state.slots[activeSlot];
  const host = document.getElementById("featureList");
  host.innerHTML = "";
  for (const f of FEATURES) {
    const li = document.createElement("li");
    li.className = "setting-item";
    li.innerHTML = `
      <div class="setting-text">
        <div class="setting-title">${f.label}</div>
        <div class="setting-subtitle">${f.sub}</div>
      </div>
      <label class="switch">
        <input type="checkbox" data-key="${f.key}" ${slot[f.key] ? "checked" : ""}>
        <span class="track"></span><span class="thumb"></span>
      </label>`;
    li.querySelector("input").addEventListener("change", (e) => {
      slot[f.key] = e.target.checked;
      persistLocal();
    });
    host.appendChild(li);
  }
}

function collectCurrent() {
  ensureSlot(activeSlot);
  const slot = state.slots[activeSlot];
  document.querySelectorAll('#featureList input[type=checkbox]').forEach((el) => {
    slot[el.dataset.key] = el.checked;
  });
  persistLocal();
}

function renderAll() {
  renderTabs();
  renderFeatures();
}

// ---- actions ----
async function applyConfig() {
  collectCurrent();
  const b64 = b64encode(JSON.stringify(state));
  const res = document.getElementById("applyResult");
  res.textContent = "应用中…"; res.className = "apply-result";
  try {
    const { stdout } = await exec(`sh ${MODDIR}/bin/apply.sh ${b64}`);
    const ok = stdout && stdout.includes('"ok":true');
    res.textContent = ok ? "已应用" : "失败";
    res.className = "apply-result " + (ok ? "ok" : "err");
    toast(ok ? "已应用配置" : "应用失败");
    if (ok) setTimeout(refreshStatus, 1500);
  } catch (e) {
    res.textContent = "失败"; res.className = "apply-result err";
    toast("应用失败");
  }
}

async function refreshStatus() {
  let stdout = "";
  try {
    const r = await exec(`sh ${MODDIR}/bin/status.sh`);
    stdout = r.stdout || "";
  } catch (_) {}
  const host = document.getElementById("statusView");
  let data = null;
  try { data = stdout ? JSON.parse(stdout.trim()) : null; } catch (_) {}
  if (!data || !data.slots || !data.slots.length) {
    host.innerHTML = `<div class="status-empty">暂无状态，点“应用”后刷新</div>`;
    return;
  }
  host.innerHTML = "";
  const t = new Date(data.lastApplyMillis || 0);
  const timeStr = isNaN(t) ? "-" : t.toLocaleString();
  const head = document.createElement("div");
  head.className = "status-empty";
  head.textContent = "最近应用：" + timeStr;
  host.appendChild(head);
  for (const s of data.slots) {
    const row = document.createElement("div");
    row.className = "status-row";
    let badge = `<span class="status-badge">未应用</span>`;
    if (s.applied) badge = `<span class="status-badge on">已应用</span>`;
    else if (s.error) badge = `<span class="status-badge err">失败</span>`;
    const ims = s.imsRegistered
      ? `<span class="status-badge on">IMS 已注册</span>`
      : `<span class="status-badge">IMS 未注册</span>`;
    row.innerHTML = `<span>卡槽 ${s.slotIndex}</span> ${badge} ${ims}`;
    host.appendChild(row);
  }
}

async function loadVersion() {
  try {
    const { stdout } = await exec(`cat ${MODDIR}/module.prop`);
    const m = stdout && stdout.match(/^version=(.+)$/m);
    if (m) document.getElementById("version").textContent = m[1];
  } catch (_) {}
}

// ---- boot ----
document.addEventListener("DOMContentLoaded", async () => {
  loadLocal();
  await loadVersion();
  await loadConfig();
  ensureSlot(activeSlot);
  document.getElementById("applyBtn").addEventListener("click", applyConfig);
  document.getElementById("refreshBtn").addEventListener("click", refreshStatus);
  refreshStatus();
});
