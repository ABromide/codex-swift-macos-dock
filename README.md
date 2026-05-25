# Codex Dock Notifier

一个 Swift 写的 macOS 小工具，用来监听本机 Codex 会话日志，并在 Codex 完成任务后通过 Dock、状态栏和系统通知提醒你。

## 界面示意

![状态栏用量缩略图](docs/images/menu-usage-summary.png)

## 功能

- 监听 `~/.codex/sessions` 下的本地 Codex session JSONL 文件。
- 检测到新的 `final_answer` 后发送 macOS 右上角通知。
- 让 Dock 图标跳动，并用 Dock badge 显示未读完成数。
- 在状态栏菜单中显示用量缩略图，包括今日、7 天、30 天 token 和近 7 天柱状图。
- 提供完整的使用量统计窗口，包括 daily、7 天、30 天、模型用量、session 排行、柱状图和折线图。
- 支持登录时自动启动。

## 数据来源

工具只读取本机 Codex 数据，不需要网络访问。

主要数据源：

```text
~/.codex/sessions
~/.codex/session_index.jsonl
~/.codex/state_5.sqlite
```

统计逻辑：

- 完成提醒来自 session JSONL 中的 `response_item`，且 `phase` 为 `final_answer`。
- token 用量来自 `event_msg` 中的 `token_count.last_token_usage`。
- 线程名称来自 `session_index.jsonl`。
- 模型名称优先读取 `state_5.sqlite` 中的 `threads.model`，读取不到时回退为 JSONL/provider/`unknown`。

## 构建和运行

```bash
make run
```

首次运行时，macOS 会请求通知权限。第一次扫描会把已有 Codex session 作为基线，不会把历史完成记录全部弹出来。

## 使用量统计

状态栏点击 `Codex` 后，可以看到顶部用量缩略图。

点击菜单里的 `使用量统计` 可以打开完整统计窗口，当前包含：

- 总 token
- 今日 token
- 7 天 token
- 30 天 token
- session 数和完成次数
- 按天 token 堆叠柱状图
- 累计 token 折线图
- 模型用量横向柱状图
- session 用量排行表

目前没有内置美元成本估算，因为 Codex 本地日志没有稳定价格表。后续可以加一个本地 `pricing.json`，按模型配置 input、cached input、output、reasoning 单价后计算成本。

## 登录时自动启动

安装登录启动项：

```bash
make install-login-item
```

移除登录启动项：

```bash
make uninstall-login-item
```

## 本地状态

工具会记录已经扫描到的位置和已经提醒过的完成事件，避免重复通知。

状态文件位置：

```text
~/Library/Application Support/CodexDockNotifier/state.json
```

## 说明

- 这是一个本地工具，不上传 Codex 日志或统计数据。
- 点击 Dock 图标或通知时，会尝试打开 Codex app。
- `.app` 图标由 `Scripts/make-app-icon.swift` 在构建时生成，并打包到 `Contents/Resources/AppIcon.icns`。
