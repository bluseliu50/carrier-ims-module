// Carrier IMS WebUI — Material 3 styled, vanilla JS, no bundler.
//
// KernelSU manager injects the WebUI API as the global `window.ksu` (NOT a
// `kernelsu` ES module — only SukiSU/WebUI-X inject that). The native methods
// we use:
//   ksu.exec(cmd)            -> synchronous, returns stdout (string)
//   ksu.exec(cmd, callback)  -> async, calls callback(code, stdout, stderr)
//   ksu.toast(msg)           -> native toast
// APatch and Magisk-based managers expose a compatible `ksu`/`kernelsu` global;
// we probe both, and fall back to a no-op so the page still renders.

const ksu = window.ksu || window.kernelsu;

// Synchronous shell: returns stdout string (empty on failure).
function sh(cmd) {
  if (!ksu || typeof ksu.exec !== "function") return "";
  try {
    // Native ksu.exec is synchronous and returns stdout directly.
    return ksu.exec(cmd) || "";
  } catch (e) {
    return "";
  }
}

function showToast(msg) {
  try { if (ksu && typeof ksu.toast === "function") ksu.toast(msg); } catch (_) {}
}

// ---- feature definitions (defaults mirror Feature.kt) ----
const FEATURES = [
  { key: "volte",            label: "VoLTE",        sub: "高清通话" },
  { key: "vowifi",           label: "VoWiFi",       sub: "Wi-Fi 通话" },
  { key: "vt",               label: "视频通话",      sub: "ViLTE" },
  { key: "vonr",             label: "VoNR",         sub: "5G 语音（需 Android 14+）" },
  { key: "crossSim",         label: "跨 SIM 通话",   sub: "Cross-SIM Calling" },
  { key: "ut",               label: "UT 补充业务",   sub: "补充服务 over UT" },
  { key: "fiveGnr",          label: "5G NR",        sub: "启用 5G" },
  { key: "fiveGPlusIcon",    label: "5G+ 图标",      sub: "NR Advanced 图标" },
  { key: "fiveGThresholds",  label: "5G 信号阈值",   sub: "信号强度分级" },
  { key: "show4gForLte",     label: "LTE 显示为 4G", sub: "状态栏图标", def: false },
  { key: "tiktokNetworkFix", label: "TikTok 修复",   sub: "自动应用 CN 国家码", def: false },
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
function loadConfig() {
  const stdout = sh(`sh ${MODDIR}/bin/read-config.sh`);
  if (stdout) {
    try {
      const cfg = JSON.parse(stdout.trim());
      if (cfg && cfg.slots) state.slots = cfg.slots;
    } catch (_) {}
  }
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
function applyConfig() {
  collectCurrent();
  const b64 = b64encode(JSON.stringify(state));
  const res = document.getElementById("applyResult");
  res.textContent = "应用中…"; res.className = "apply-result";
  const out = sh(`sh ${MODDIR}/bin/apply.sh ${b64}`);
  let info = null;
  try { info = out ? JSON.parse(out.trim()) : null; } catch (_) {}
  if (!info || !info.ok) {
    res.textContent = "失败：" + ((info && info.error) || "未知错误");
    res.className = "apply-result err";
    showToast("应用失败");
    return;
  }
  res.textContent = "已应用"; res.className = "apply-result ok";
  showToast("已应用配置");
  // The applier writes status.json synchronously; refresh after a short delay.
  setTimeout(refreshStatus, 600);
}

function refreshStatus() {
  const stdout = sh(`sh ${MODDIR}/bin/status.sh`);
  const host = document.getElementById("statusView");
  let data = null;
  try { data = stdout ? JSON.parse(stdout.trim()) : null; } catch (_) {}
  if (!data || !data.slots || !data.slots.length) {
    host.innerHTML = `<div class="status-empty">暂无状态，点“应用”后刷新</div>`;
    return;
  }
  host.innerHTML = "";
  const d = new Date(data.lastApplyMillis || 0);
  const timeStr = isNaN(d) ? "-" :
    `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
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

function pad(n) { return n < 10 ? "0" + n : "" + n; }

function loadVersion() {
  // ksu.exec uses fastCmd which returns only the FIRST line, so grep the
  // version line explicitly instead of catting the whole file.
  const stdout = sh(`grep '^version=' ${MODDIR}/module.prop`);
  const m = stdout && stdout.match(/^version=(.+)$/m);
  if (m) document.getElementById("version").textContent = m[1];
}

// Check the applier dex is present (the apply path depends on it).
function checkApplier() {
  const host = document.getElementById("version");
  const ok = sh(`ls ${MODDIR}/system/bin/Applier.dex`).trim().length > 0;
  const dot = document.createElement("span");
  dot.style.cssText =
    "display:inline-block;width:8px;height:8px;border-radius:50%;margin-left:8px;vertical-align:middle;background:" +
    (ok ? "var(--md-success)" : "var(--md-error)");
  dot.title = ok ? "Applier 就绪" : "Applier 缺失（模块未生效）";
  host.appendChild(dot);
}

// ---- boot ----
document.addEventListener("DOMContentLoaded", () => {
  loadLocal();
  loadVersion();
  loadConfig();
  checkApplier();
  ensureSlot(activeSlot);
  document.getElementById("applyBtn").addEventListener("click", applyConfig);
  document.getElementById("refreshBtn").addEventListener("click", refreshStatus);
  refreshStatus();
});
