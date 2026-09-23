# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

- 对话流展示模型**思考过程**：Kimi 等模型的 `reasoning_content` 经流式接口
  捕获，在每步正文/工具调用前以「· 思考：…」独立成行渲染（屏上 `TuiRole.thinking`）；
  底层 LLM 调用由非流式改为**流式**端点（`chat()` 内部走 `chatStream` 累积，
  思考过程不再丢失）。
- 开启规划轮（`planning`）：nava 对每条新任务先让模型用 `plan_write` 产出执行
  计划，屏上 TODO 列表（目标 + 步骤 + 完成标记）随之出现，执行过程从第一步可见；
  `ConatusTuiRuntime.createController` / `ConatusTuiController` 新增 `planning`
  参数（缺省 `false`，nava 入口开启）。
- 对话流展示 agent 执行过程，不再只是一问一答：
  - 工具调用名始终逐条显示（此前会被助手文本吞掉），工具结果保留完整内容；
    超过 8 行折叠为摘要，`Ctrl+O` 展开 / 收起最近一条工具详情。
  - 计划（TODO 列表）随 `plan/updated` 事件在屏上更新（目标 + 步骤 + 完成标记，
    默认展开），`Ctrl+T` 折叠 / 展开。
  - 团队视图入口由 `Ctrl+T` 改为 `/team`（Esc 返回对话）。
- 新增 `/permission` 命令：打开权限模式选择面板（`↑↓` 选择、`Enter` 切换、`Esc`
  取消，当前模式带 `← 当前` 标记）；选中后持久化到当前会话（与审批浮层里的
  切换选项共用同一机制），不再需要记忆参数名。
- 会话 id 统一为 `session_<uuid>`（如 `session_c8898262-4a76-4bd4-93dc-f757fd4ef666`）：
  - `nava` 不带 `--session`、`--session` 无值、或取值不是 `session_<uuid>` 格式时，
    一律**新建会话**，不再回落到 `tui` / 恢复历史会话；只有显式传规范格式 id 才
    打开/恢复对应会话。
  - **破坏性**：`TuiOptions.session` 改为可空（`null` = 新建会话），`parse` 移除
    `sessionId` 参数，常量 `kTuiDefaultSession` 删除；`ConatusTuiRuntime.createController`
    的 `initialSession` 缺省为 `null`（新建会话）。旧会话文件（`tui.jsonl` 等）不删除，
    TUI 内 `/session` / `/sessions` 仍可访问。
- provider 配置收敛到 config.toml：新增 `[providers.<名字>]` 表（`api_key` /
  `base_url` / `type` / 可选 `oauth` 子表）与 `[llm] default_model =
  "provider/model"`；`providers.json` 不再读写，`[llm] provider` / `model`
  两个字段被 `default_model` 替代，模型 Key 不再走 `[credentials]`/环境变量
  （`[credentials]` 表保留给搜索等非模型 Key）
- `/provider` 命令退化为只读展示；增删改直接编辑 config.toml
- **破坏性**：`ConatusTuiRuntime.create` 移除 `providers`（bool）/`providersFile`
  形参，新增 `List<ProviderConfig>? providers`；已有 `providers.json` 的用户
  需把 provider 定义迁移到 config.toml 的 `[providers.xxx]`
- 破坏性变更：移除 `--first` 启动参数与 `AgentTui.firstInput`。`TuiOptions.first` /
  `AgentTui.firstInput` 不再存在，`--first` 不再被识别（按未知参数忽略）。
- `[llm] provider` 配置接线：`ConatusTuiRuntime.create` 新增 `provider` 形参，按
  注册表名选提供商，缺省用当前项。
- `conatus_providers` 并入本包：`ProviderProfile` / `ProviderRegistry` /
  `ProviderStore` / registry 导入与内置默认清单移入 `lib/src/providers/`，公开入口
  为 `lib/providers.dart`（与 `tui.dart` / `fs_tools.dart` / `coding.dart` 并列）；
  原独立包与根伞包的再导出一并移除。新增 `http` 直接依赖（registry 导入用）。
- 去掉缺省回退链：不再提供 `defaultFallbackLlm`。`ConatusTuiRuntime.create` 未显式
  传 `llm` 时用注册表当前提供商构造，两者都拿不到时抛 `StateError`；
  `DoubaoProvider` / `DeepSeekProvider` 作为显式构造的便捷类保留。
- 沙箱分层（Layer 1 / Layer 2 解耦）：
  - 新增 `fs_jail`（Layer 1 应用层文件 jail，默认开启，纯应用层不依赖 OS
    后端）；`enabled` 仅指 Layer 2 OS 级沙箱（命令执行）。
  - fail-closed 只作用于 Layer 2 后端：后端不可用时新增
    `RejectingShellExecutor` 禁用命令执行（不降级本地 shell、不整体退出），
    Layer 1 文件 jail 照常生效。
  - 新增 `resolveSandboxLayers`（`sandbox_assembly.dart`）统一两层装配。
- 沙箱默认启用：`[sandbox] enabled`（Layer 2）与 `fs_jail`（Layer 1）缺省
  `true`；不支持 OS 后端的机器命令执行自动禁用（fail-closed），文件 jail 保留。
- 自愈闭环（M4）：
  - 新增预算模块 `lib/src/budget/`：`TurnBudget`（每轮墙钟 + 上下文 token 估算
    护栏，默认 10 分钟 / 20 万 token，`estimateMessagesTokens` 粗口径只作护栏）；
    `BudgetedLlmProvider` 包装 `'llm'` 服务，超限返回收口提示而非报错（空闲
    2 分钟视为新一轮）；首个 `CostTracker` 实现 `CostTrackerImpl`（按用量与
    粗略单价累计 `todayCost`），注册到 `'costTracker'` 供自主运行消费。
    `ConatusTuiRuntime.create` 新增 `turnBudget` 参数（可显式关闭）。
  - 新增 `update_plan` 工具：执行中按步骤序号标记完成 / 改写文案 / 追加步骤，
    写回 `plan/updated` 事件；会话装配补齐 `plan_write`（此前未注册），
    计划闭环成形。
  - system prompt 增补「先规划后执行、失败反思重试」指引。
  - 自主运行接线：新增 `provideAutonomous`（会话级装配 `'autonomousRunner'`，
    独立 Agent Loop 避免与 goalDriver 双算），`costTracker` 惰性解析自根上下文，
    预算超限触发 `budgetExceeded` 停止。
  - 配置新增 `[budget]`：`max_turn_seconds` / `max_turn_tokens`（`0` = 不限），
    由 `bin/conatus_code.dart` 映射为 `TurnBudget`。
- 新增 macOS 沙箱（M3，Seatbelt + dart_io_sandbox）：
  - `lib/src/sandbox/`：`probeSandboxBackend`（launcher 定位 + chmod + 试跑，
    fail-closed）、`CommandPolicy`（命令形状裁决）、`SandboxedShellExecutor`
    （经 launcher 最小环境执行，不继承父环境）、`JailedFileSystem`
    （conatus `FileSystem` 接 bound jail，越界映射 `sandboxDenied`）；
    `run_command` / `run_tests` 走沙箱接缝（high 风险）。
  - 配置新增 `[sandbox]`：`enabled`（默认 true）、`network_allowlist`、
    `allowed_executables`、`command_timeout_ms`、`max_output_bytes`。
  - `tool/sandbox_probe.dart` 输出后端探测结果。
- 输入栏支持粘贴图片/文件：Ctrl+V 读系统剪贴板图片（macOS，经 osascript），
  粘贴文本中的文件路径（终端拖放 / `file://` URL）识别为附件；附件以 chip
  展示在输入栏上方（Backspace 可移除），提交时图片转 `LlmImage` 随消息发给
  模型、文本文件内联为 `<file>` 块。新增 `tui_attachment` / `tui_clipboard_image`

- 依赖新增 `conatus_compaction`：压缩服务（`provideCompaction`）由该包提供，
  装配时改从新包导入。
- 多智能体协作 UI（HANDOFF-12）：
  - 依赖新增 `conatus_team`、`conatus_tts`
  - 新增 `TeamSnapshot` / `ViewMode` 与 `TeamSubscription`（订阅
    `AgentTeam.changes`，事件驱动重建快照，可选成本 seam `TeamCostSource`）
  - 新增团队渲染件：`TeamStatusBar`（团队概况）、`MemberCard`、`TaskRow`、
    `TeamView`（成员列表 + 任务板）
  - 会话装配团队服务（`provideAgentTeam` + `provideTeamTools`），模型可用团队
    协作工具；`Ctrl+T` 切换对话 / 团队视图（输入框内优先于文本域转置快捷键）
  - 新增 `VoiceReporter`（订阅团队事件经 TTS 播报，`minInterval` 节流 + 可选
    音频目标）与 `summarizeTeamProgress` 进度摘要
  - 新增斜杠命令 `/team`（status / interrupt）与 `/task`（claim / release）
- `conatus_tui` `/cron add` 支持中文规则词（每天 / 每周X）与间隔单位
  （秒 / 分钟 / 小时）。
- 技能斜杠命令：每个已发现的技能投影成 `/skill:<技能名> [补充要求]`，进 `/` 菜单过滤；
  执行时把技能正文展开成一轮用户输入（照常进 `user/message`），屏上折回一行。
  `disable-model-invocation` 的技能对模型隐藏但用户能手动触发。
  - 新增 `skillTuiCommands` / `renderSkillPrompt` / `collapseSkillPrompt`
  - `TuiCommandMenu` 支持注入命令来源（缺省仍是静态表），
    `ConatusTuiController.commands` 给出「静态 + 技能」的合并表
  - `Transcript` 把展开的技能正文块折叠回 `/skill:<技能名> …` 再上屏
- 再导出 `nocterm`：调用方只需依赖 `conatus_tui` 即可使用 `runApp` /
  `shutdownApp` / `Component` 等类型。仅屏蔽 nocterm 自带的 `isEmpty` /
  `isNotEmpty`（与 `package:test` 同名冲突）。
- 入口的命令行解析提为公开 API：新增 `TuiOptions.parse(args)`、`TuiOptions.usage`
  与 `kTuiDefaultSession`，调用方自己的入口可直接复用；`--help` 只置
  `helpRequested`，不再在解析里打印用法并退出。
- `example/deepseek_demo.dart` 改用 `TuiOptions`：`--session` / `--first` /
  `--help` 走公开解析，Demo 专属的 `--model` 由 `parseModelFlag` 补取；默认会话
  随之统一为 `kTuiDefaultSession`（tui）。
- `TuiOptions.parse` 支持 `sessionId` 参数：`--session` 未出现时用它（缺省
  `kTuiDefaultSession`），`--session` 合法时以它为准；最终选中的会话 id 非法时
  抛 `ArgumentError`。`isValidSessionId` 随之移到 `tui_options.dart`（对外签名
  不变）。

## [0.15.0] — 2026-09-15

- 新增 `conatus_tui`：基于 [nocterm](https://pub.dev/packages/nocterm) 的文本 TUI。
  用 conatus Agent Loop 驱动多轮对话，会话事件投射为屏上消息，含斜杠命令菜单、
  会话选择面板、顶栏 / 状态栏与工具调用回显；支持 JSONL 会话持久化与恢复。
- 新增 DeepSeek Demo（`example/deepseek_demo.dart`）：用 `DeepSeekProvider` 驱动
  TUI，未设置 `DEEPSEEK_API_KEY` 时退回离线脚本模型，无 Key 也能预览。
- `ConatusTuiRuntime.create` 支持注入 `llm` 与覆盖 `modelLabel`。
