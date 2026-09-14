# Codex Day

Codex 右上角的 **Day** 按钮，展开或收起两张毛玻璃便利贴：月历 + 每日待办。没有独立 dashboard 窗口。

- Apple Calendar 实时读取；已确认待办可双向同步至 Apple Reminders 专用 `Codex Day` 列表。
- 本地每日 00:00 提取 Codex 对话中的明确清单/待办段落；休眠后补执行。同一天不重复扫描，不调用模型、不消耗 token。
- 建议先审核再加入，支持编辑、改日期、完成和删除；手动修改不会被每日扫描覆盖。
- 运行时毛玻璃主题可移除，不改官方 `.app`、`app.asar`、签名或 Codex 设置。

## 安装

要求 macOS 14+、官方 Codex/ChatGPT 桌面端，以及已有 Swift 命令行工具和 `/usr/bin/python3`。无需 npm/pip 安装运行依赖。

```sh
./scripts/build.sh
python3 scripts/install.py
```

安装仅写入自己的 `~/Library/Application Support/Codex Day/`、`~/Applications/Codex with Day.app` 和三个 `~/Library/LaunchAgents/local.codex.day.*.plist`。后台 EventKit helper 没有窗口或 Dock 图标。

日常从 `~/Applications/Codex with Day.app` 打开 Codex。这个固定入口没有 dashboard 窗口，会验证官方应用签名并带上扩展参数；如果 Codex 已正常打开，会提示你正常退出后自动重新打开。不要再依赖临时重开脚本。

也可关闭 Codex 后从命令行启动：

```sh
./scripts/enable-interface.sh
```

该脚本拒绝终止正在运行的 Codex。扩展通过经过进程与签名校验的 `127.0.0.1:9341` 连接注入。使用原官方图标启动不会携带扩展参数，仍需改用 `Codex with Day` 入口。无法在不修改官方安装包的前提下替换其原生启动行为。首次点击连接按钮时，在 macOS 中授权 Calendar / Reminders。

`codex-day/` 是插件源码（含 `.codex-plugin/plugin.json` 与 skill），可注册到个人 marketplace。插件目录的安装与后台运行组件分别管理：单独安装 manifest 无法增加官方横栏按钮，必须运行上述本机扩展。

## 使用

Regular glass 为默认可读材质；底部按钮可切换更通透的 Clear glass。正文和滚动容器不加模糊，面板适配深浅模式与增强对比度/减少透明度设置。

点击 **Day** 或按 **⌘⇧D** 开关；**Esc** 收起。点击月历日期查看当天待办；Unscheduled 保存无日期事项；Suggestions 审核本地提取结果。

Calendar 只读。Reminders 只管理专用列表；启用后同步本地已有待办，在 Reminders 中编辑/完成/删除会反映到面板。其他设备同步依赖该列表所属 Apple 账户本身的同步能力。面板打开时约每 5 秒更新一次；EventKit 同时监听系统变更。

**提取范围与限制：**读取本机 Codex 主任务的完整可读历史，包括归档任务；不包括云端专属 ChatGPT 聊天和子代理。规则识别未勾选清单、TODO/待办、Next steps 等段落，识别同名已勾选和明确取消项。它不是 AI 语义汇总，可能遗漏自然语言任务或保留过期建议，所以必须审核；不确定日期保留为未排期。

## 移除

```sh
python3 scripts/uninstall.py
```

仅移除本项目后台任务及运行文件，保留 `tasks.json`、`suggestions.json` 和 Apple Reminders。正常退出并重新打开 Codex，即恢复原界面并关闭调试端口。个人 marketplace 中的插件可在 Codex Plugins 页面单独卸载。

## 开发

```sh
python3 -m unittest discover -s tests -v
node --test tests/bridge.test.mjs
./scripts/build.sh
```

无需上传或提交个人聊天、日历、待办、令牌、构建缓存。设计与接入参考 [Codex Dream Skin](https://github.com/Fei-Away/Codex-Dream-Skin)，兼容选择器来自其公开合同；实现为独立本机扩展，不代表官方支持任意横栏插件。

材质设计参考 [Apple Materials](https://developer.apple.com/design/human-interface-guidelines/materials) 与 [LiquidGlass for Obsidian v1.5.14](https://github.com/GavinKalvin/LiquidGlass_plugin/releases/tag/v1.5.14)。其原生模块仅适配特定 Obsidian/Electron 版本，本项目不加载该模块或使用私有折射效果。
