// Claude Sounds Plugin - Web UI

const API = "";  // same origin

// ── i18n ───────────────────────────────────────────────────────────────────────

function applyLang() {
  const set = (id, key) => { const el = document.getElementById(id); if (el) el.textContent = t(key); };
  const attr = (id, attr, key) => { const el = document.getElementById(id); if (el) el[attr] = t(key); };

  // Header
  set("badge-text",           "loading");
  attr("plugin-toggle-label", "title", "pluginToggleTip");
  set("lang-btn",             "langToggle");

  // Tabs
  set("tab-btn-status",  "tabStatus");
  set("tab-btn-themes",  "tabThemes");
  set("tab-btn-store",   "tabStore");
  set("tab-btn-project", "tabProject");

  // Status tab
  set("lbl-current-theme", "currentTheme");
  set("lbl-global-theme",  "globalTheme");
  set("lbl-hooks",         "hooks");
  set("btn-stop-ui",       "stopUi");

  // Themes tab
  set("lbl-installed-themes", "installedThemes");
  set("lbl-themes-loading",   "loading");
  set("lbl-install-local",    "installLocal");
  set("lbl-upload-hint",      "uploadHint");
  set("lbl-upload-sub",       "uploadSub");

  // Store tab
  set("lbl-store-desc",    "storeDesc");
  set("btn-refresh",       "refresh");
  set("lbl-store-loading", "fetchingStore");

  // Project tab
  set("lbl-project-list",   "projectList");
  set("lbl-select-project", "selectProject");
  attr("manual-path", "placeholder", "pastePathHint");

  // Re-render dynamic content if loaded
  if (state.status)  renderStatus();
  if (state.themes.length) renderThemes();
  if (state.store)   renderStore();
  if (state.activeTab === "project") renderProjectList();

  // html lang attr
  document.documentElement.lang = getLang() === "zh" ? "zh-CN" : "en";
}

function toggleLang() {
  setLang(getLang() === "zh" ? "en" : "zh");
  applyLang();
}

// ── Utils ──────────────────────────────────────────────────────────────────────

async function api(method, path, body) {
  const opts = { method, headers: {} };
  if (body !== undefined) {
    opts.headers["Content-Type"] = "application/json";
    opts.body = JSON.stringify(body);
  }
  const res = await fetch(API + path, opts);
  return res.json();
}

let toastTimer;
function toast(msg, type = "success") {
  const el = document.getElementById("toast");
  el.textContent = msg;
  el.className = `show ${type}`;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.className = "", 3000);
}

function setLoading(el, loading) {
  if (loading) {
    el._orig = el.innerHTML;
    el.innerHTML = '<span class="spin"></span>';
    el.disabled = true;
  } else {
    el.innerHTML = el._orig || el.innerHTML;
    el.disabled = false;
  }
}

// ── State ──────────────────────────────────────────────────────────────────────

let state = {
  status: null,
  themes: [],
  store: null,
  storeLoading: false,
  activeTab: "status",
  projectPath: window.PROJECT_PATH || "",
  projects: [],
};

// ── Tab routing ────────────────────────────────────────────────────────────────

function showTab(name) {
  state.activeTab = name;
  document.querySelectorAll(".tab").forEach(t =>
    t.classList.toggle("active", t.dataset.tab === name)
  );
  document.querySelectorAll(".tab-pane").forEach(p =>
    p.style.display = p.id === `tab-${name}` ? "" : "none"
  );
  if (name === "themes")  loadThemes();
  if (name === "store")   loadStore();
  if (name === "project") {
    if (!state.themes.length) loadThemes().then(loadProjectTab);
    else loadProjectTab();
  }
}

// ── Status tab ─────────────────────────────────────────────────────────────────

async function loadStatus() {
  const data = await api("GET", "/api/status");
  state.status = data;
  renderStatus();
}

function renderStatus() {
  const s = state.status;
  if (!s) return;

  // Header badge
  const badge = document.getElementById("header-badge");
  badge.className = `badge ${s.enabled ? "on" : "off"}`;
  badge.innerHTML = `<span class="dot"></span>${s.enabled ? t("running") : t("stopped")}`;

  // Plugin toggle
  document.getElementById("plugin-enabled").checked = s.enabled;

  // Theme label
  document.getElementById("current-theme").textContent = s.theme;

  // Hooks
  const hooks = s.hooks || {};
  const hookDescKeys = {
    stop:         "hookStop",
    notification: "hookNotification",
    error:        "hookError",
    permission:   "hookPermission",
  };
  const container = document.getElementById("hooks-list");
  container.innerHTML = Object.entries(hookDescKeys).map(([h, key]) => `
    <div class="toggle">
      <div class="toggle-label">
        <span>${h}</span>
        <span class="toggle-desc">${t(key)}</span>
      </div>
      <label class="switch">
        <input type="checkbox" id="hook-${h}" ${hooks[h] !== false ? "checked" : ""}
               onchange="setHook('${h}', this.checked)">
        <span class="slider"></span>
      </label>
    </div>
  `).join("");
}

async function setEnabled(val) {
  await api("POST", "/api/enable", { enabled: val });
  state.status.enabled = val;
  renderStatus();
  toast(val ? t("pluginEnabled") : t("pluginDisabled"));
}

async function setHook(hook, val) {
  await api("POST", "/api/hook", { hook, enabled: val });
  state.status.hooks[hook] = val;
  toast(`${hook} ${val ? t("hookOn") : t("hookOff")}`);
}

// ── Themes tab ─────────────────────────────────────────────────────────────────

async function loadThemes() {
  const data = await api("GET", "/api/themes");
  state.themes = data.themes || [];
  renderThemes();
}

function renderThemes() {
  const container = document.getElementById("themes-grid");
  if (!state.themes.length) {
    container.innerHTML = `<div class="empty"><div class="empty-icon">🎵</div>${t("noThemes")}</div>`;
    return;
  }

  container.innerHTML = state.themes.map(th => `
    <div class="theme-card ${th.active ? "active" : ""}" onclick="switchTheme('${th.name}')">
      <div class="theme-name">${th.display_name || th.name}</div>
      <div class="theme-meta">
        v${th.version || "—"}
        ${th.builtin ? ` · <span style="color:var(--blue)">${t("builtin")}</span>` : ""}
      </div>
      <div class="theme-actions" onclick="event.stopPropagation()">
        <button class="btn btn-sm" onclick="previewTheme('${th.name}', this)">${t("preview")}</button>
        ${!th.active ? `<button class="btn btn-sm btn-primary" onclick="switchTheme('${th.name}')">${t("switchTheme")}</button>` : `<span style="font-size:12px;color:var(--accent)">${t("currentActive")}</span>`}
        ${!th.builtin ? `<button class="btn btn-sm btn-danger" onclick="removeTheme('${th.name}', this)">${t("deleteTheme")}</button>` : ""}
      </div>
    </div>
  `).join("");
}

async function switchTheme(name) {
  await api("POST", "/api/theme", { name });
  state.status.theme = name;
  state.themes.forEach(th => th.active = (th.name === name));
  renderThemes();
  document.getElementById("current-theme").textContent = name;
  toast(t("switchedTheme", name));
}

async function previewTheme(name, btn) {
  setLoading(btn, true);
  const res = await api("POST", "/api/theme/preview", { name, sound: "notification" });
  setLoading(btn, false);
  if (!res.ok) toast(res.error || t("previewFail"), "error");
}

async function removeTheme(name, btn) {
  if (!confirm(t("confirmDelete", name))) return;
  setLoading(btn, true);
  const res = await api("DELETE", `/api/theme/${name}`);
  if (res.ok) {
    toast(t("deletedTheme", name));
    await loadThemes();
  } else {
    toast(res.error || t("deleteFail"), "error");
    setLoading(btn, false);
  }
}

// Upload .cstheme
function initUpload() {
  const zone = document.getElementById("upload-zone");
  const input = document.getElementById("upload-input");

  zone.addEventListener("click", () => input.click());
  zone.addEventListener("dragover", e => { e.preventDefault(); zone.classList.add("drag"); });
  zone.addEventListener("dragleave", () => zone.classList.remove("drag"));
  zone.addEventListener("drop", e => {
    e.preventDefault();
    zone.classList.remove("drag");
    const file = e.dataTransfer.files[0];
    if (file) uploadFile(file);
  });
  input.addEventListener("change", () => {
    if (input.files[0]) uploadFile(input.files[0]);
  });
}

async function uploadFile(file) {
  if (!file.name.endsWith(".cstheme")) {
    toast(t("uploadWrongType"), "error"); return;
  }
  const zone = document.getElementById("upload-zone");
  zone.innerHTML = `<div class="spin"></div> ${t("uploadInstalling")}`;
  const fd = new FormData();
  fd.append("file", file);
  const res = await fetch("/api/theme/upload", { method: "POST", body: fd });
  const data = await res.json();
  zone.innerHTML = `<div class="upload-icon">📦</div>${t("uploadHint")}`;
  if (data.ok) {
    toast(t("uploadSuccess"));
    await loadThemes();
  } else {
    toast(data.error || t("uploadFail"), "error");
  }
}

// ── Store tab ──────────────────────────────────────────────────────────────────

async function loadStore() {
  if (state.storeLoading) return;
  state.storeLoading = true;
  document.getElementById("store-list").innerHTML = `<div class="loading"><span class="spin"></span>${t("fetchingStore")}</div>`;
  const data = await api("GET", "/api/store");
  state.storeLoading = false;
  if (data.ok === false) {
    document.getElementById("store-list").innerHTML = `<div class="empty"><div class="empty-icon">⚠️</div>${data.error}</div>`;
    return;
  }
  state.store = data.themes || [];
  renderStore();
}

function renderStore() {
  const container = document.getElementById("store-list");
  if (!state.store.length) {
    container.innerHTML = `<div class="empty"><div class="empty-icon">📭</div>${t("noStoreThemes")}</div>`;
    return;
  }
  container.innerHTML = state.store.map(th => `
    <div class="store-item">
      <div class="store-info">
        <div class="store-name">${th.display_name || th.name}</div>
        <div class="store-desc">${th.description || ""}</div>
        <div class="store-author">by ${th.author || "—"} · ${((th.size || 0) / 1024).toFixed(0)} KB</div>
      </div>
      <div>
        ${th.installed
          ? `<span class="badge on"><span class="dot"></span>${t("installed")}</span>`
          : `<button class="btn btn-primary btn-sm" onclick="installTheme('${th.name}', this)">${t("install")}</button>`
        }
      </div>
    </div>
  `).join("");
}

async function installTheme(name, btn) {
  setLoading(btn, true);
  const res = await api("POST", "/api/store/install", { name });
  if (res.ok) {
    toast(t("installSuccess", name));
    state.store = null;
    state.storeLoading = false;
    await loadStore();
    if (state.activeTab === "themes") await loadThemes();
  } else {
    toast(res.error || t("installFail"), "error");
    setLoading(btn, false);
  }
}

function refreshStore() {
  state.store = null;
  state.storeLoading = false;
  loadStore();
}

// ── Project tab ────────────────────────────────────────────────────────────────

function getProjectPath() {
  return document.getElementById("project-path").value || state.projectPath;
}

function addManualProject() {
  const input = document.getElementById("manual-path");
  const path  = input.value.trim();
  if (!path) return;
  input.value = "";
  addAndSelectProject(path);
}

function addAndSelectProject(path) {
  const name = path.split("/").pop() || path;
  // Add to list if not present
  if (!state.projects.find(p => p.path === path)) {
    state.projects.unshift({ path, name, theme: "", hooks: {}, no_config: true });
  }
  renderProjectList();
  selectProject(path);
}

async function loadProjectTab() {
  document.getElementById("project-list").innerHTML =
    '<div class="loading"><span class="spin"></span></div>';
  const data = await api("GET", "/api/projects");
  state.projects = data.projects || [];
  renderProjectList();
  // Auto-select cwd
  const cwd = state.projects.find(p => p.is_cwd);
  if (cwd) selectProject(cwd.path);
}

function renderProjectList() {
  const list = document.getElementById("project-list");
  if (!state.projects.length) {
    list.innerHTML = '<div style="font-size:12px;color:var(--text2);padding:8px 0">暂无已配置项目</div>';
    return;
  }
  list.innerHTML = state.projects.map(p => `
    <div class="proj-item ${p.path === getProjectPath() ? "active" : ""}"
         onclick="selectProject('${p.path.replace(/'/g, "\\'")}')">
      <div class="proj-name">${p.name}</div>
      <div class="proj-path">${p.path}</div>
      ${p.is_cwd ? `<div class="proj-badge">${t("currentDir")}</div>` : ""}
      ${p.theme  ? `<div class="proj-badge">${t("themeLabel")}: ${p.theme}</div>` : ""}
    </div>
  `).join("");
}

async function selectProject(path) {
  document.getElementById("project-path").value = path;
  state.projectPath = path;
  renderProjectList();  // re-render to update active state
  document.getElementById("project-detail").innerHTML =
    `<div class="loading"><span class="spin"></span>${t("loading")}</div>`;
  const data = await api("GET", `/api/project?path=${encodeURIComponent(path)}`);
  renderProject(data);
}

function renderProject(data) {
  const cfg    = data.config || {};
  const exists = data.exists;

  const hookDescs = {
    stop:         "任务完成时播放",
    notification: "需要输入时播放",
    error:        "出错时播放",
    permission:   "工具调用前播放",
  };
  const hooks      = cfg.hooks || {};
  const themes     = state.themes.length ? state.themes : [];
  const current    = cfg.theme || "";
  const globalTheme = state.status?.theme || "default";

  const themeOptions = themes.map(t =>
    `<option value="${t.name}" ${t.name === current ? "selected" : ""}>${t.display_name || t.name}${t.builtin ? " (内置)" : ""}</option>`
  ).join("");

  document.getElementById("project-detail").innerHTML = `
    <div class="card">
      <div class="card-title" style="display:flex;justify-content:space-between;align-items:center">
        <span>${t("themeLabel")}</span>
        <span style="font-size:11px;color:var(--text2);font-weight:400">${t("globalDefault")}: ${globalTheme}</span>
      </div>
      <div class="toggle">
        <span>${t("projectTheme")}</span>
        <select id="proj-theme-select" onchange="setProjectTheme(this.value)"
          style="background:var(--bg3);border:1px solid var(--border);border-radius:6px;
                 padding:6px 10px;color:var(--text);font-size:13px;outline:none;cursor:pointer">
          <option value="" ${!current ? "selected" : ""}>${t("useGlobal")}</option>
          ${themeOptions}
        </select>
      </div>
    </div>

    <div class="card">
      <div class="card-title" style="display:flex;justify-content:space-between;align-items:center">
        <span>${t("hooksOverride")}</span>
        ${exists ? `<button class="btn btn-sm btn-danger" onclick="clearProject()">${t("clearConfig")}</button>` : ""}
      </div>
      ${Object.entries(hookDescs).map(([h, desc]) => {
        const hasOverride = h in hooks;
        return `
        <div class="toggle">
          <div class="toggle-label">
            <span>${h}</span>
            <span class="toggle-desc">${desc}${hasOverride
              ? ` · <span style="color:var(--accent)">${t("overridden")}</span>`
              : ` · ${t("usingGlobal")}`}</span>
          </div>
          <div style="display:flex;gap:8px;align-items:center">
            ${hasOverride ? `<button class="btn btn-sm" style="padding:3px 7px" onclick="clearProjectHook('${h}')" title="${t("overrideCleared", h)}">✕</button>` : ""}
            <label class="switch">
              <input type="checkbox" ${(hasOverride ? hooks[h] : true) !== false ? "checked" : ""}
                     onchange="setProjectHook('${h}', this.checked)">
              <span class="slider"></span>
            </label>
          </div>
        </div>`;
      }).join("")}
    </div>
  `;

  // Sync project list entry
  const proj = state.projects.find(p => p.path === getProjectPath());
  if (proj) { proj.theme = current; proj.no_config = !exists; }
  renderProjectList();
}

async function setProjectTheme(name) {
  const path = getProjectPath();
  if (!path) return;
  await api("POST", "/api/project/theme", { path, name });
  toast(name ? t("themeSet", name) : t("themeGlobal"));
  const data = await api("GET", `/api/project?path=${encodeURIComponent(path)}`);
  renderProject(data);
}

async function setProjectHook(hook, val) {
  const path = getProjectPath();
  if (!path) return;
  await api("POST", "/api/project/hook", { path, hook, enabled: val });
  toast(`项目 ${hook} ${val ? "已开启" : "已关闭"}`);
  const data = await api("GET", `/api/project?path=${encodeURIComponent(path)}`);
  renderProject(data);
}

async function clearProjectHook(hook) {
  const path = getProjectPath();
  if (!path) return;
  await api("POST", "/api/project/hook/clear", { path, hook });
  toast(t("overrideCleared", hook));
  const data = await api("GET", `/api/project?path=${encodeURIComponent(path)}`);
  renderProject(data);
}

async function clearProject() {
  const path = getProjectPath();
  if (!path) return;
  if (!confirm(t("confirmClear"))) return;
  await api("POST", "/api/project/clear", { path });
  toast(t("configCleared"));
  // Remove from list
  state.projects = state.projects.filter(p => p.path !== path || p.is_cwd);
  const data = await api("GET", `/api/project?path=${encodeURIComponent(path)}`);
  renderProject(data);
  renderProjectList();
}

// ── Init ───────────────────────────────────────────────────────────────────────

async function stopServer() {
  if (!confirm(t("confirmStop"))) return;
  await fetch("/api/shutdown", { method: "POST" }).catch(() => {});
  document.body.innerHTML = `<div style="display:flex;align-items:center;justify-content:center;height:100vh;color:#888;font-family:sans-serif;flex-direction:column;gap:12px"><div style="font-size:32px">■</div><div>${t("stoppedMsg")}</div><div style="font-size:12px">${t("stoppedSub")}</div></div>`;
}

document.addEventListener("DOMContentLoaded", async () => {
  // Tab clicks
  document.querySelectorAll(".tab").forEach(t =>
    t.addEventListener("click", () => showTab(t.dataset.tab))
  );

  // Plugin toggle
  document.getElementById("plugin-enabled").addEventListener("change", function () {
    setEnabled(this.checked);
  });

  // Upload
  initUpload();

  // Project path input
  // project-path is now a hidden field, no listener needed

  // Apply language
  applyLang();

  // Load initial data
  await loadStatus();
  // Pre-fill project path with server's cwd
  const cwdData = await api("GET", "/api/cwd");
  if (cwdData.cwd) {
    state.projectPath = cwdData.cwd;
    document.getElementById("project-path").value = cwdData.cwd;
  }
  showTab("status");
});
