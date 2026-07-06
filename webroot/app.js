// Carrier IMS WebUI — vanilla JS, no bundler.
// Uses the manager-provided global `kernelsu` API (KernelSU/APatch/MMRL all
// expose a compatible exec). Configuration state mirrors config.json.

// ---- toggle definitions (defaults mirror Feature.kt) ----
const TOGGLES = [
  { key: "volte",            label: "VoLTE",            def: true },
  { key: "vowifi",           label: "VoWiFi",           def: true },
  { key: "vt",               label: "视频通话 VT",       def: true },
  { key: "vonr",             label: "VoNR",             def: true },
  { key: "crossSim",         label: "跨 SIM 通话",       def: true },
  { key: "ut",               label: "UT 补充业务",       def: true },
  { key: "fiveGnr",          label: "5G NR",            def: true },
  { key: "fiveGThresholds",  label: "5G 信号阈值",       def: true },
  { key: "fiveGPlusIcon",    label: "5G+ 图标",          def: true },
  { key: "show4gForLte",     label: "LTE 显示为 4G",     def: false },
];

const MODID = "carrier_ims";
const MODDIR = "/data/adb/modules/" + MODID;
const CONFIG_DEFAULT = {
  enabled: false, applyOnBoot: true, applyOnSimChange: true, slots: {}
};

// ---- shell exec wrapper (handles Promise + callback kernelsu variants) ----
function sh(cmd) {
  return new Promise((resolve) => {
    const ksu = window.kernelsu || window.ksu;
    if (!ksu || typeof ksu.exec !== "function") {
      resolve({ errno: -1, stdout: "", stderr: "kernelsu API not available" });
      return;
    }
    try {
      const r = ksu.exec(cmd);
      if (r && typeof r.then === "function") {
        r.then(resolve).catch((e) => resolve({ errno: -1, stdout: "", stderr: String(e) }));
      } else if (typeof r === "object") {
        resolve(r);
      } else {
        resolve({ errno: -1, stdout: "", stderr: "unexpected exec result" });
      }
    } catch (e) {
      resolve({ errno: -1, stdout: "", stderr: String(e) });
    }
  });
}

function toast(msg) {
  const ksu = window.kernelsu || window.ksu;
  if (ksu && typeof ksu.toast === "function") { try { ksu.toast(msg); return; } catch (_) {} }
}

// ---- base64 helpers (UTF-8 safe) ----
function b64encode(str) {
  const bytes = new TextEncoder().encode(str);
  let bin = "";
  bytes.forEach((b) => (bin += String.fromCharCode(b)));
  return btoa(bin);
}

// ---- state ----
let state = JSON.parse(JSON.stringify(CONFIG_DEFAULT));
let activeSlot = 0;

function ensureSlot(slot) {
  if (!state.slots[slot]) {
    const s = {};
    for (const t of TOGGLES) s[t.key] = t.def;
    s.carrierName = ""; s.countryIso = ""; s.countryMccOverride = "";
    state.slots[slot] = s;
  }
}

// ---- render toggles ----
function renderToggles() {
  const host = document.getElementById("toggles");
  host.innerHTML = "";
  ensureSlot(activeSlot);
  const slot = state.slots[activeSlot];
  for (const t of TOGGLES) {
    const id = "tg-" + t.key;
    const wrap = document.createElement("label");
    wrap.className = "toggle";
    wrap.innerHTML = `<input type="checkbox" id="${id}" ${slot[t.key] ? "checked" : ""}><span>${t.label}</span>`;
    host.appendChild(wrap);
    document.getElementById(id).addEventListener("change", (e) => {
      slot[t.key] = e.target.checked;
      persistLocal();
    });
  }
}

// ---- bind text fields for the active slot ----
function bindSlotFields() {
  ensureSlot(activeSlot);
  const slot = state.slots[activeSlot];
  const fields = ["carrierName", "countryIso", "countryMccOverride"];
  for (const f of fields) {
    const el = document.getElementById(f);
    el.value = slot[f] || "";
    el.oninput = () => { slot[f] = el.value; persistLocal(); };
  }
}

// ---- localStorage persistence of edits (authoritative copy is config.json) ----
function persistLocal() {
  try { localStorage.setItem("carrierims_state", JSON.stringify(state)); } catch (_) {}
}
function loadLocal() {
  try {
    const s = localStorage.getItem("carrierims_state");
    if (s) state = Object.assign(JSON.parse(JSON.stringify(CONFIG_DEFAULT)), JSON.parse(s));
  } catch (_) {}
}

// ---- load config.json from device ----
async function loadConfig() {
  const { stdout } = await sh(`sh ${MODDIR}/bin/read-config.sh`);
  let cfg = null;
  try { cfg = stdout ? JSON.parse(stdout.trim()) : null; } catch (_) {}
  if (cfg) {
    state.enabled = !!cfg.enabled;
    state.applyOnBoot = cfg.applyOnBoot !== false;
    state.applyOnSimChange = cfg.applyOnSimChange !== false;
    state.slots = cfg.slots || {};
  }
  syncForm();
}

// ---- sync UI from state ----
function syncForm() {
  document.getElementById("masterEnabled").checked = !!state.enabled;
  document.getElementById("applyOnBoot").checked = !!state.applyOnBoot;
  document.getElementById("applyOnSimChange").checked = !!state.applyOnSimChange;
  bindSlotFields();
  renderToggles();
}

// ---- collect current UI into state ----
function collectForm() {
  state.enabled = document.getElementById("masterEnabled").checked;
  state.applyOnBoot = document.getElementById("applyOnBoot").checked;
  state.applyOnSimChange = document.getElementById("applyOnSimChange").checked;
  ensureSlot(activeSlot);
  const slot = state.slots[activeSlot];
  for (const t of TOGGLES) slot[t.key] = document.getElementById("tg-" + t.key).checked;
  slot.carrierName = document.getElementById("carrierName").value;
  slot.countryIso = document.getElementById("countryIso").value;
  slot.countryMccOverride = document.getElementById("countryMccOverride").value;
  persistLocal();
}

// ---- actions ----
async function applyConfig() {
  collectForm();
  const json = JSON.stringify(state);
  const b64 = b64encode(json);
  document.getElementById("applyResult").textContent = "应用中…";
  const { stdout, stderr } = await sh(`sh ${MODDIR}/bin/apply.sh ${b64}`);
  const ok = stdout && stdout.includes('"ok":true');
  document.getElementById("applyResult").textContent = ok ? "✓ 已应用" : "✗ 失败";
  toast(ok ? "已应用配置" : "应用失败");
  setTimeout(refreshStatus, 1200);
}

async function refreshStatus() {
  const { stdout } = await sh(`sh ${MODDIR}/bin/status.sh`);
  let pretty = stdout || "{}";
  try { pretty = JSON.stringify(JSON.parse(stdout.trim()), null, 2); } catch (_) {}
  document.getElementById("statusView").textContent = pretty;
}

async function cpAction(op) {
  const { stdout, stderr } = await sh(`sh ${MODDIR}/bin/captive-portal.sh ${op}`);
  document.getElementById("cpView").textContent = (stdout || stderr || "").trim();
}

async function loadVersion() {
  const { stdout } = await sh(`cat ${MODDIR}/module.prop`);
  if (stdout) {
    const m = stdout.match(/^version=(.+)$/m);
    if (m) document.getElementById("version").textContent = m[1];
  }
}

// ---- wire up ----
document.addEventListener("DOMContentLoaded", async () => {
  loadLocal();
  await loadVersion();
  await loadConfig();

  document.getElementById("applyBtn").addEventListener("click", applyConfig);
  document.getElementById("refreshBtn").addEventListener("click", refreshStatus);
  document.getElementById("cpFix").addEventListener("click", () => cpAction("fix"));
  document.getElementById("cpRestore").addEventListener("click", () => cpAction("restore"));
  document.getElementById("cpQuery").addEventListener("click", () => cpAction("query"));

  ["masterEnabled", "applyOnBoot", "applyOnSimChange"].forEach((id) =>
    document.getElementById(id).addEventListener("change", persistLocal));

  document.querySelectorAll(".tab").forEach((btn) =>
    btn.addEventListener("click", () => {
      collectForm();
      document.querySelectorAll(".tab").forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");
      activeSlot = parseInt(btn.dataset.slot, 10);
      bindSlotFields();
      renderToggles();
    }));

  refreshStatus();
});
