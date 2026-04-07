// Claude Sounds UI - i18n
const LANGS = {
  zh: {
    // Header
    loading:           "加载中",
    running:           "运行中",
    stopped:           "已停用",
    pluginToggleTip:   "启用/禁用插件",
    langToggle:        "EN",

    // Tabs
    tabStatus:         "状态",
    tabThemes:         "主题",
    tabStore:          "商店",
    tabProject:        "项目配置",

    // Status tab
    currentTheme:      "当前主题",
    globalTheme:       "全局主题",
    hooks:             "Hooks",
    stopUi:            "停止 Web UI 服务",
    pluginEnabled:     "插件已启用",
    pluginDisabled:    "插件已停用",

    // Hook descriptions
    hookStop:          "任务完成时播放",
    hookNotification:  "需要输入时播放",
    hookError:         "出错时播放",
    hookPermission:        "工具调用前播放（默认关闭）",
    hookPermissionRequest: "权限弹框出现时播放",
    hookOn:            "已开启",
    hookOff:           "已关闭",

    // Themes tab
    installedThemes:   "已安装主题",
    installLocal:      "安装本地主题",
    uploadHint:        "拖拽或点击安装 .cstheme 文件",
    uploadSub:         "支持本地打包的主题包",
    uploadInstalling:  "安装中...",
    uploadSuccess:     "主题安装成功",
    uploadFail:        "安装失败",
    uploadWrongType:   "只支持 .cstheme 文件",
    preview:           "▶ 试听",
    switchTheme:       "切换",
    deleteTheme:       "删除",
    currentActive:     "当前使用",
    builtin:           "内置",
    confirmDelete:     (name) => `删除主题 "${name}"?`,
    deletedTheme:      (name) => `已删除: ${name}`,
    deleteFail:        "删除失败",
    switchedTheme:     (name) => `主题已切换为: ${name}`,
    previewFail:       "试听失败",
    noThemes:          "暂无主题",

    // Store tab
    storeDesc:         "从 GitHub 主题商店浏览和安装主题",
    refresh:           "↻ 刷新",
    fetchingStore:     "正在获取主题商店...",
    noStoreThemes:     "商店暂无主题",
    installed:         "已安装",
    install:           "安装",
    installSuccess:    (name) => `${name} 安装成功`,
    installFail:       "安装失败",

    // Project tab
    projectList:       "项目列表",
    pastePathHint:     "粘贴项目路径",
    selectProject:     "👈 从左侧选择一个项目",
    currentDir:        "● 当前目录",
    themeLabel:        "主题",
    projectTheme:      "项目主题",
    globalDefault:     "全局",
    useGlobal:         "(使用全局)",
    hooksOverride:     "Hooks 覆盖",
    overridden:        "已覆盖",
    usingGlobal:       "使用全局",
    clearConfig:       "清除项目配置",
    confirmClear:      "清除项目配置？将回退到全局设置。",
    configCleared:     "项目配置已清除",
    themeSet:          (name) => `项目主题已设为: ${name}`,
    themeGlobal:       "已恢复使用全局主题",
    overrideCleared:   (h) => `${h} 覆盖已取消`,

    // Shutdown
    confirmStop:       "停止 Web UI 服务？",
    stoppedMsg:        "服务已停止",
    stoppedSub:        "重新运行 /sounds:cs ui 启动",
  },

  en: {
    // Header
    loading:           "Loading",
    running:           "Running",
    stopped:           "Disabled",
    pluginToggleTip:   "Enable/disable plugin",
    langToggle:        "中文",

    // Tabs
    tabStatus:         "Status",
    tabThemes:         "Themes",
    tabStore:          "Store",
    tabProject:        "Projects",

    // Status tab
    currentTheme:      "Current Theme",
    globalTheme:       "Global Theme",
    hooks:             "Hooks",
    stopUi:            "Stop Web UI",
    pluginEnabled:     "Plugin enabled",
    pluginDisabled:    "Plugin disabled",

    // Hook descriptions
    hookStop:          "Play on task complete",
    hookNotification:  "Play when input needed",
    hookError:         "Play on error",
    hookPermission:        "Play before tool use (off by default)",
    hookPermissionRequest: "Play when permission dialog appears",
    hookOn:            "enabled",
    hookOff:           "disabled",

    // Themes tab
    installedThemes:   "Installed Themes",
    installLocal:      "Install Local Theme",
    uploadHint:        "Drag & drop or click to install .cstheme",
    uploadSub:         "Supports locally packed theme files",
    uploadInstalling:  "Installing...",
    uploadSuccess:     "Theme installed",
    uploadFail:        "Installation failed",
    uploadWrongType:   "Only .cstheme files are supported",
    preview:           "▶ Preview",
    switchTheme:       "Use",
    deleteTheme:       "Delete",
    currentActive:     "Active",
    builtin:           "built-in",
    confirmDelete:     (name) => `Delete theme "${name}"?`,
    deletedTheme:      (name) => `Deleted: ${name}`,
    deleteFail:        "Delete failed",
    switchedTheme:     (name) => `Theme switched to: ${name}`,
    previewFail:       "Preview failed",
    noThemes:          "No themes installed",

    // Store tab
    storeDesc:         "Browse and install themes from the GitHub store",
    refresh:           "↻ Refresh",
    fetchingStore:     "Fetching theme store...",
    noStoreThemes:     "No themes available in store",
    installed:         "Installed",
    install:           "Install",
    installSuccess:    (name) => `${name} installed`,
    installFail:       "Installation failed",

    // Project tab
    projectList:       "Projects",
    pastePathHint:     "Paste project path",
    selectProject:     "👈 Select a project from the left",
    currentDir:        "● Current dir",
    themeLabel:        "Theme",
    projectTheme:      "Project Theme",
    globalDefault:     "Global",
    useGlobal:         "(use global)",
    hooksOverride:     "Hooks Override",
    overridden:        "overridden",
    usingGlobal:       "using global",
    clearConfig:       "Clear Project Config",
    confirmClear:      "Clear project config? Will fall back to global settings.",
    configCleared:     "Project config cleared",
    themeSet:          (name) => `Project theme set to: ${name}`,
    themeGlobal:       "Reverted to global theme",
    overrideCleared:   (h) => `${h} override removed`,

    // Shutdown
    confirmStop:       "Stop the Web UI server?",
    stoppedMsg:        "Server stopped",
    stoppedSub:        "Run /sounds:cs ui to restart",
  },
};

let _lang = localStorage.getItem("cs-lang") || "zh";

function t(key, ...args) {
  const val = LANGS[_lang]?.[key] ?? LANGS.zh[key] ?? key;
  return typeof val === "function" ? val(...args) : val;
}

function setLang(lang) {
  _lang = lang;
  localStorage.setItem("cs-lang", lang);
}

function getLang() { return _lang; }
