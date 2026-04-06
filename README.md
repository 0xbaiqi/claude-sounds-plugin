# Claude Sounds Plugin

让 Claude Code 在关键事件时播放提示音，支持主题切换、项目级配置和图形化管理界面。

## 界面预览

![状态页](assets/index.png)

![主题管理](assets/themes.png)

![主题商店](assets/shop.png)

## 功能

- 任务完成、需要输入、工具调用时播放声音
- 图形化 Web UI，可视化管理所有配置
- 支持主题（内置默认主题，可从商店安装更多）
- 每个项目可配置不同主题和 hook 开关
- 跨平台：macOS / Linux / Windows
- 零额外依赖（纯 Shell + Python3 标准库）

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

## 使用

### 图形界面（推荐）

```
/sounds:cs ui
```

自动打开浏览器，提供可视化管理：
- 开关插件和各个 Hook
- 浏览、试听、切换主题
- 从商店安装主题
- 拖拽安装本地 `.cstheme` 文件
- 按项目配置不同的主题和 Hook

### 命令行

所有操作也可通过 `/sounds:cs` 命令完成：

```
/sounds:cs               查看当前配置
/sounds:cs help          查看完整帮助
```

#### 基本控制

```
/sounds:cs enable        启用插件
/sounds:cs disable       禁用插件
```

#### Hook 管理

```
/sounds:cs hook status               查看各 hook 状态
/sounds:cs hook enable permission    开启工具调用提示音
/sounds:cs hook disable stop         关闭任务完成提示音
```

#### 主题商店

```
/sounds:cs theme store list              查看可用主题
/sounds:cs theme store install mario     安装主题
/sounds:cs theme store update            更新所有主题
```

#### 本地主题

```
/sounds:cs theme list                    查看已安装主题
/sounds:cs theme <name>                  切换主题
/sounds:cs theme pack ./mytheme          打包自制主题
/sounds:cs theme install ./my.cstheme    安装本地主题包
/sounds:cs theme remove  <name>          删除主题
/sounds:cs theme cache-clear             清除缓存
```

#### 项目级配置

在项目根目录运行，只影响当前项目：

```
/sounds:cs project theme mario           当前项目用 mario 主题
/sounds:cs project hook disable stop     当前项目关闭 stop
/sounds:cs project hook status           查看项目 hook 配置
/sounds:cs project status                查看完整项目配置
/sounds:cs project clear                 清除项目配置
```

#### 测试

```
/sounds:cs test          依次播放所有声音
/sounds:cs test stop     只测试 stop
```

## 主题格式

主题包为 `.cstheme` 文件（自定义二进制格式，含 SHA256 完整性校验）。

制作方法：

1. 准备一个文件夹，放入 4 个 MP3 + `manifest.json`：

```
mytheme/
  stop.mp3          任务完成
  notification.mp3  需要输入
  error.mp3         出错
  permission.mp3    工具调用前
  manifest.json     {"name":"mytheme","display_name":"My Theme","version":"1.0.0"}
```

2. 打包并安装：

```
/sounds:cs theme pack ./mytheme
/sounds:cs theme install ./mytheme.cstheme
/sounds:cs theme mytheme
```

音效只需一个也可以，4 个文件复制同一份即可。欢迎向 [claude-sounds-themes](https://github.com/0xbaiqi/claude-sounds-themes) 提交主题。

## 用户数据

所有配置和主题存储在 `~/.claude/claude-sounds-xapipro/`：

```
config.json     全局配置（主题、开关、hooks、已注册项目列表）
themes/         用户安装的主题
cache/          自动解压的音频缓存（可随时清除）
```

项目配置存储在各项目的 `.claude/sounds.json`。

## 卸载

```bash
bash uninstall.sh
```

## 协议

MIT
