# Claude Sounds Plugin

让 Claude Code 在关键事件时播放提示音，支持主题切换和项目级配置。

## 功能

- 任务完成、需要输入、工具调用时播放声音
- 支持主题（内置默认主题，可从商店安装更多）
- 每个项目可配置不同主题和 hook 开关
- 跨平台：macOS / Linux / Windows
- 零额外依赖

## 支持的事件

| 事件 | 触发时机 | 默认 |
|------|---------|------|
| Stop | 任务完成 | ✅ 开启 |
| Notification | 需要你输入 | ✅ 开启 |
| Error | 出错时 | ✅ 开启 |
| Permission | 每次工具调用前 | ❌ 关闭 |

## 安装

```bash
git clone https://github.com/0xbaiqi/claude-sounds-plugin
cd claude-sounds-plugin
bash install.sh
```

重启 Claude Code 生效。

开发模式（无需安装）：

```bash
claude --plugin-dir /path/to/claude-sounds-plugin
```

## 使用

所有管理操作通过 `/sounds:cs` 命令完成：

```
/sounds:cs               查看当前配置
/sounds:cs help          查看完整帮助
```

### 基本控制

```
/sounds:cs enable        启用插件
/sounds:cs disable       禁用插件
```

### Hook 管理

```
/sounds:cs hook enable permission    开启工具调用提示音
/sounds:cs hook disable stop         关闭任务完成提示音
/sounds:cs hook status               查看各 hook 状态
```

### 主题商店

```
/sounds:cs theme store list              查看可用主题
/sounds:cs theme store preview cyberpunk 试听主题
/sounds:cs theme store install cyberpunk 安装主题
/sounds:cs theme store update            更新所有主题
```

### 本地主题

```
/sounds:cs theme list                    查看已安装主题
/sounds:cs theme pack ./mytheme          打包自制主题
/sounds:cs theme install ./my.cstheme   安装本地主题包
/sounds:cs theme <name>                  切换主题
```

### 项目级配置

在项目根目录运行，只影响当前项目：

```
/sounds:cs project theme lofi            当前项目用 lofi 主题
/sounds:cs project hook disable stop     当前项目关闭 stop
/sounds:cs project status                查看项目配置
```

### 测试

```
/sounds:cs test          依次播放所有声音
/sounds:cs test stop     只测试 stop
```

## 主题格式

主题包为 `.cstheme` 文件（自定义格式，含完整性校验）。

制作方法：准备 4 个 MP3 + `manifest.json`，运行：

```bash
/sounds:cs theme pack ./mytheme-dir
```

欢迎向 [claude-sounds-themes](https://github.com/0xbaiqi/claude-sounds-themes) 提交主题。

## 卸载

```bash
bash uninstall.sh
```

## 协议

MIT
