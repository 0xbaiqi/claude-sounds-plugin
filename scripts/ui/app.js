// Claude Sounds Plugin - Web UI

const API = "";  // same origin

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
  badge.innerHTML = `<span class="dot"></span>${s.enabled ? "运行中" : "已停用"}`;

  // Plugin toggle
  document.getElementById("plugin-enabled").checked = s.enabled;

  // Theme label
  document.getElementById("current-theme").textContent = s.theme;

  // Hooks
  const hooks = s.hooks || {};
  const hookDescs = {
    stop:         "任务完成时播放",
    notification: "需要输入时播放",
    error:        "出错时播放",
    permission:   "工具调用前播放（默认关闭）",
  };
  const container = document.getElementById("hooks-list");
  container.innerHTML = Object.entries(hookDescs).map(([h, desc]) => `
    <div class="toggle">
      <div class="toggle-label">
        <span>${h}</span>
        <span class="toggle-desc">${desc}</span>
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
  toast(val ? "插件已启用" : "插件已停用");
}

async function setHook(hook, val) {
  await api("POST", "/api/hook", { hook, enabled: val });
  state.status.hooks[hook] = val;
  toast(`${hook} ${val ? "已开启" : "已关闭"}`);
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
    container.innerHTML = '<div class="empty"><div class="empty-icon">🎵</div>暂无主题</div>';
    return;
  }

  container.innerHTML = state.themes.map(t => `
    <div class="theme-card ${t.active ? "active" : ""}" onclick="switchTheme('${t.name}')">
      <div class="theme-name">${t.display_name || t.name}</div>
      <div class="theme-meta">
        v${t.version || "—"}
        ${t.builtin ? ' · <span style="color:var(--blue)">内置</span>' : ""}
      </div>
      <div class="theme-actions" onclick="event.stopPropagation()">
        <button class="btn btn-sm" onclick="previewTheme('${t.name}', this)" title="试听">▶ 试听</button>
        ${!t.active ? `<button class="btn btn-sm btn-primary" onclick="switchTheme('${t.name}')">切换</button>` : `<span style="font-size:12px;color:var(--accent)">当前使用</span>`}
        ${!t.builtin ? `<button class="btn btn-sm btn-danger" onclick="removeTheme('${t.name}', this)">删除</button>` : ""}
      </div>
    </div>
  `).join("");
}

async function switchTheme(name) {
  await api("POST", "/api/theme", { name });
  state.status.theme = name;
  state.themes.forEach(t => t.active = (t.name === name));
  renderThemes();
  document.getElementById("current-theme").textContent = name;
  toast(`主题已切换为: ${name}`);
}

async function previewTheme(name, btn) {
  setLoading(btn, true);
  const res = await api("POST", "/api/theme/preview", { name, sound: "notification" });
  setLoading(btn, false);
  if (!res.ok) toast(res.error || "试听失败", "error");
}

async function removeTheme(name, btn) {
  if (!confirm(`删除主题 "${name}"?`)) return;
  setLoading(btn, true);
  const res = await api("DELETE", `/api/theme/${name}`);
  if (res.ok) {
    toast(`已删除: ${name}`);
    await loadThemes();
  } else {
    toast(res.error || "删除失败", "error");
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
    toast("只支持 .cstheme 文件", "error"); return;
  }
  const zone = document.getElementById("upload-zone");
  zone.innerHTML = '<div class="spin"></div> 安装中...';
  const fd = new FormData();
  fd.append("file", file);
  const res = await fetch("/api/theme/upload", { method: "POST", body: fd });
  const data = await res.json();
  zone.innerHTML = `<div class="upload-icon">📦</div>拖拽或点击安装 .cstheme 文件`;
  if (data.ok) {
    toast("主题安装成功");
    await loadThemes();
  } else {
    toast(data.error || "安装失败", "error");
  }
}

// ── Store tab ──────────────────────────────────────────────────────────────────

async function loadStore() {
  if (state.storeLoading) return;
  state.storeLoading = true;
  document.getElementById("store-list").innerHTML = '<div class="loading"><span class="spin"></span>正在获取主题商店...</div>';
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
    container.innerHTML = '<div class="empty"><div class="empty-icon">📭</div>商店暂无主题</div>';
    return;
  }
  container.innerHTML = state.store.map(t => `
    <div class="store-item">
      <div class="store-info">
        <div class="store-name">${t.display_name || t.name}</div>
        <div class="store-desc">${t.description || ""}</div>
        <div class="store-author">by ${t.author || "—"} · ${((t.size || 0) / 1024).toFixed(0)} KB</div>
      </div>
      <div>
        ${t.installed
          ? `<span class="badge on"><span class="dot"></span>已安装</span>`
          : `<button class="btn btn-primary btn-sm" onclick="installTheme('${t.name}', this)">安装</button>`
        }
      </div>
    </div>
  `).join("");
}

async function installTheme(name, btn) {
  setLoading(btn, true);
  const res = await api("POST", "/api/store/install", { name });
  if (res.ok) {
    toast(`${name} 安装成功`);
    state.store = null;
    state.storeLoading = false;
    await loadStore();
    if (state.activeTab === "themes") await loadThemes();
  } else {
    toast(res.error || "安装失败", "error");
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

function onFolderPick(input) {
  const files = input.files;
  if (!files.length) return;
  // Try to get absolute path (works in Electron/Claude Code's built-in browser)
  let absPath = "";
  for (const f of files) {
    if (f.path) {
      const rel  = f.webkitRelativePath || f.name;
      const root = rel.split("/")[0];
      absPath = f.path.substring(0, f.path.lastIndexOf(rel) + root.length);
      break;
    }
  }
  if (absPath) {
    addAndSelectProject(absPath);
  } else {
    toast("浏览器限制：无法获取绝对路径", "error");
  }
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
      ${p.is_cwd ? '<div class="proj-badge">● 当前目录</div>' : ""}
      ${p.theme  ? `<div class="proj-badge">主题: ${p.theme}</div>` : ""}
    </div>
  `).join("");
}

async function selectProject(path) {
  document.getElementById("project-path").value = path;
  state.projectPath = path;
  renderProjectList();  // re-render to update active state
  document.getElementById("project-detail").innerHTML =
    '<div class="loading"><span class="spin"></span>加载中...</div>';
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
        <span>主题</span>
        <span style="font-size:11px;color:var(--text2);font-weight:400">全局: ${globalTheme}</span>
      </div>
      <div class="toggle">
        <span>项目主题</span>
        <select id="proj-theme-select" onchange="setProjectTheme(this.value)"
          style="background:var(--bg3);border:1px solid var(--border);border-radius:6px;
                 padding:6px 10px;color:var(--text);font-size:13px;outline:none;cursor:pointer">
          <option value="" ${!current ? "selected" : ""}>(使用全局)</option>
          ${themeOptions}
        </select>
      </div>
    </div>

    <div class="card">
      <div class="card-title" style="display:flex;justify-content:space-between;align-items:center">
        <span>Hooks 覆盖</span>
        ${exists ? `<button class="btn btn-sm btn-danger" onclick="clearProject()">清除项目配置</button>` : ""}
      </div>
      ${Object.entries(hookDescs).map(([h, desc]) => {
        const hasOverride = h in hooks;
        return `
        <div class="toggle">
          <div class="toggle-label">
            <span>${h}</span>
            <span class="toggle-desc">${desc}${hasOverride
              ? ` · <span style="color:var(--accent)">已覆盖</span>`
              : " · 使用全局"}</span>
          </div>
          <div style="display:flex;gap:8px;align-items:center">
            ${hasOverride ? `<button class="btn btn-sm" style="padding:3px 7px" onclick="clearProjectHook('${h}')" title="取消覆盖">✕</button>` : ""}
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
  toast(name ? `项目主题已设为: ${name}` : "已恢复使用全局主题");
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
  toast(`${hook} 覆盖已取消`);
  const data = await api("GET", `/api/project?path=${encodeURIComponent(path)}`);
  renderProject(data);
}

async function clearProject() {
  const path = getProjectPath();
  if (!path) return;
  if (!confirm("清除项目配置？将回退到全局设置。")) return;
  await api("POST", "/api/project/clear", { path });
  toast("项目配置已清除");
  // Remove from list
  state.projects = state.projects.filter(p => p.path !== path || p.is_cwd);
  const data = await api("GET", `/api/project?path=${encodeURIComponent(path)}`);
  renderProject(data);
  renderProjectList();
}

// ── Init ───────────────────────────────────────────────────────────────────────

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
  document.getElementById("project-path").addEventListener("change", loadProject);

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
