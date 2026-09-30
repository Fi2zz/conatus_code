# Nava

> A terminal coding agent built on the conatus runtime.

## 是什么

基于 [conatus](https://github.com/Fi2zz/conatus) 构建的终端编码智能体。
复用 conatus 的 Agent Loop、工具系统、技能沉淀，
专注 coding 场景。

## 特性

- 🖥️ 终端交互（内置 TUI，入口 `lib/tui.dart`）
- 🔍 文件读写与搜索（read_file / write_file / edit_file / rg / glob）
- 🧠 技能沉淀（重复轨迹自动抽象为可复用工具）
- 🤝 多智能体协作（任务板 + 成员运行时）
- 🔒 审批与沙箱（高危操作走审批；默认 Seatbelt 进程沙箱 + 文件 jail）
- 🗺️ 计划闭环（plan_write 建计划、update_plan 执行中推进、计划面板实时渲染）
- 🩹 失败自愈（工具失败自动反思重试，可按需重规划）
- ⏱️ 预算护栏（每轮墙钟 + 上下文 token 估算 + 成本跟踪）

## 快速开始

```bash
# 从源码运行
git clone https://github.com/Fi2zz/conatus_code.git
cd conatus_code
dart pub get
dart run bin/conatus_code.dart
```

## 打包成可执行文件

```bash
bash tool/build_binary.sh
```

产出 `dist/nava`（自包含：内嵌 Dart runtime，目标机器不需要装 Dart SDK）。
装到 PATH 的两种方式：

```bash
# 1. 软链到 PATH 上的目录
ln -s "$PWD/dist/nava" /usr/local/bin/nava

# 2. 或把 dist/ 加进 PATH
export PATH="$PWD/dist:$PATH"
```

之后直接 `nava` 启动，`nava --help` 看用法。脚本默认写到
`<包根>/dist/nava`；第一个参数可覆盖输出路径，例如把产物写到
`/tmp/nava`。

注意：OS 沙箱后端（launcher）仍在运行时从 pub 缓存定位，换机器或清理 pub 缓存后
沙箱会 fail-closed（命令执行被禁用，文件 jail 保留），这与源码运行时的行为一致。

## 配置

首次运行会读取 `~/.nava/config.toml`（`NAVA_HOME` / `--config` 可覆盖路径）。
**文件不存在时自动生成模板，并弹出 provider 面板引导添加**（会话内 `/provider`
也可随时新增，写回 config.toml）。示例：

```toml
[credentials]
ARK_API_KEY = "sk-..."        # 非模型 Key 也放这里（TAVILY_API_KEY 等）

[llm]
default_model = "arkcli-agent-plan/doubao-seed-2-0-lite-260215"   # provider/model
# fallback_models = ["deepseek/deepseek-chat"]                    # 回退链（按序）
# max_attempts = 4            # 单个提供商总尝试次数（含首次）；1 = 关闭重试
# retry_base_ms = 500         # 首次退避，此后按 2 的幂翻倍
# retry_max_ms = 30000        # 单次退避上限（Retry-After 也受此约束）

[providers.arkcli-agent-plan]
api_key = "ark-..."
base_url = "https://ark.cn-beijing.volces.com/api/plan/v3"
type = "openai"

[providers.deepseek]
api_key = "sk-..."
base_url = "https://api.deepseek.com/v1"
type = "openai"

[agent]
max_steps = 8                 # 单轮最大模型步数
workdir = "/path/to/project"  # 工作目录（沙箱根）；缺省当前目录
# project_dir = ".conatus"    # 项目数据目录（会话/记忆/数据库/检查点）；缺省不放工作区，
                              # 落 ~/.nava/projects/<编码工作区路径>；显式设置才
                              # 相对工作目录（旧行为，工作区会出现该目录）

[approval]
mode = "ask_when_needed"      # always_ask / ask_when_needed / never_ask

[sandbox]
enabled = true                # Layer 2：OS 级沙箱（命令执行）；默认开启
fs_jail = true                # Layer 1：应用层文件 jail（防误操作）；默认开启
preset = "workspace_write"    # workspace_write / danger_full_access（无 OS 沙箱）
allow_network = false         # true = 全部命令放行网络（默认拒绝，见 network_allowlist）
network_allowlist = ["git fetch", "git pull"]
allowed_executables = ["npx"] # 与内置默认白名单合并（扩展语义，只增不减）
writable_paths = []           # 额外可写路径（~ 展开、相对基于工作目录）
command_timeout_ms = 120000
max_output_bytes = 64000

[budget]
max_turn_seconds = 600        # 单轮墙钟上限（秒）；0 = 不限
max_turn_tokens = 200000      # 单轮上下文 token 估算上限；0 = 不限

[checkpoint]
enabled = true                # 每轮收口后对工作区做文件快照（/rewind 回滚）
keep = 5                      # 回滚点数（含 turn 0 全量 base；0 = 不限）
# ignore = ["app/build"]      # 额外忽略的相对路径前缀（内置已排 .git / .conatus /
                              # build / .dart_tool / node_modules 等可再生目录）

[background]
# keep_alive_on_exit = false  # true = 退出时不杀后台任务（脱离 /background 管理）
# max_running_tasks = 4       # 后台任务并发上限（0 = 不限）

# MCP server：工具经 `server__tool` 前缀接入，高危按审批模式询问。
# [mcp.servers.filesystem]
# type = "stdio"              # stdio 用 command；http / sse 用 url
# command = "npx"
# args = ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
# [mcp.servers.remote]
# type = "http"
# url = "https://mcp.example.com/mcp"
# headers = { Authorization = "Bearer ${REMOTE_TOKEN}" }
```

## 检查点与回滚（`/rewind`）

每轮收口后对工作区文件做快照：**turn 0 全量 base + 各轮相对 base 的差量**
（只打包变化/新增文件，删除记入清单），**每个检查点压缩成单个无扩展名归档
文件**（`<项目数据目录>/checkpoints/<会话>/<sha256 哈希名>`**——项目数据目录
缺省是 `~/.nava/projects/<编码工作区路径>`（不在工作区建目录），**文件名不可读、
无 `.gz` 扩展名、不暴露轮次时间线**，轮次只记录在归档头与会话级 gzip `index`
里；内容非明文、不保留目录结构；`dart:io` 内置 GZipCodec 自定义容器格式，零新
依赖；旧版目录树检查点读时兼容、索引缺失自动重建）。清单记录快照时刻的对话
切点事件 id。`/rewind [N]` 把工作区恢复到 N 轮前（缺省 1）的文件状态，**并同步
把对话回滚到该轮**：从切点事件 `Session.fork` 出新会话（append-only 不变式，
旧会话保留为记录），`/rewind list` 查看本会话可用检查点。快照/恢复走应用级
dart:io，不受 fs jail 约束；`/rewind` 是用户命令，不挂审批。

- 快照时机：会话绑定（turn 0）+ 每轮收口后；保留 base + 最近 `keep-1` 个差量。
- 排除：内置 `.git` / `.conatus` / `build` / `.dart_tool` / `node_modules`
  （顶层前缀），外加 `[checkpoint] ignore` 用户配置；读写全程流式
  （清单头单独读、条目按 chunk 过 gzip），大工作区快照内存 ≈ 最大单文件。
- 恢复语义：base 铺底 + 差量覆盖/删除 + 删当前多余（rsync 式）。
- 变化检测：相对 base 的 mtime+size + SHA-256 哈希（stat 相同也兜底）。
- 对话切点：`lastEventId` 为 null（全新会话的 turn 0）时切到全新空会话。
- 关闭：`[checkpoint] enabled = false`（/rewind 提示不可用）。

## 后台任务（`/background`）

`run_command_background` 在沙箱中后台启动命令（不阻塞对话），返回 `bg-<n>`；
`list_background_tasks` / `background_output` / `background_kill` 管理之。
`/background [list|output <id>|kill <id>]` 是用户侧入口。任务走 `'shell'` 缝的
`start()`，照常受沙箱 CommandPolicy 裁决；并发上限读 `[background]
max_running_tasks`（缺省 4）。缺省 `keep_alive_on_exit = false`：nava 退出时
终止所有在跑任务；置 `true` 则退出时不杀、任务保活脱离——**脱离后不再受
`/background` 管理**（list/output/kill 找不到它），且输出管道随进程退出关闭，
子进程继续大量写输出可能被 SIGPIPE 杀死。

## 消息队列

busy 时输入不再被拒：自动排队（上限 20 条），当前轮收口后依次投递；`Esc`
打断会**清空队列**并提示条数；切换会话同样清空。cron/提醒的投递不受影响
（busy 时仍由调度器重试）。

## `/commit` 与 `/doctor`

- `/commit`：完整提交流程——`git_status` 看未暂存的 → `git_add` 暂存 →
  `git_diff --staged` 复核 → 写 Conventional Commits 提交信息 → `git_commit`
  提交（high 风险走审批）。
- `/review`：审查当前未提交改动（命名/边界/安全/性能，**只审不改**），
  提交/提 PR 前自检。
- `/doctor`：体检——配置 / 提供商 / 回退链 / 模型窗口与费率 / 沙箱（Layer 1/2）/
  工具表 / MCP / rg 逐项 ✓/✗ + 修复提示，自查用。

### `/trace` 复盘

```
你 › 把 checkpoint 的存储后端加上 git 选项
思考 › 先看存储实现是怎么选后端的
✓ rg › lib/src/checkpoint/checkpoint_backend.dart:24（+11 行）
✗ edit_file › OS Error: Path does not exist, path = .../nope.dart
助手 › 路径写错了，改用 checkpoint_backend.dart
```

回答「模型当时看到了什么、为什么那么判断」——屏上只有结论，复盘给的是过程。
`/trace` 渲染最近一轮，`/trace 3` 看最近三轮。

会话日志本来就是可读 JSONL、事件也全都在盘上，**缺的不是数据而是能看的入口**，
所以这里不新建埋点，只把 `Session.events` 摊成时间线：

- 失败项标 `✗` 并带出原因——模型为什么停下、哪一步炸了
- 工具结果只取首行但**报出总行数**：`rg` 命中 12 处和 1 处是不同的信息，
  砍到首行不能把条数也丢了
- 不可读的事件（`agent/round` / `plan/updated` 等）跳过，不产生噪声行
- 压缩事件标出来（压缩失败也会显式提示）

`/doctor` 查的是**装配**（配置、沙箱、工具表）；`/trace` 查的是**这一轮发生了什么**。

### `/export` 导出

`/export [路径]` 把当前会话导出为 markdown —— 存档、贴给同事、喂给别的工具
分析。缺省落在项目数据目录的 `exports/`，给路径则照写（支持 `~` 展开）。

```
# nava 会话 session_abc123

- 会话：`session_abc123`
- 模型：ark/doubao-seed-2-0-lite
- 工作目录：`/Users/fitz/REPO/conatus`
- 事件：42 条
- 成本：$0.0873（models.dev 口径，非账单）

## 你
给 checkpoint 加上 git 存储后端

<details><summary>思考</summary>
先看 openCheckpointStore 怎么选后端的
</details>

### ✗ edit_file
OS Error: Path does not exist, path = 'lib/…/nope.dart'
```

与 `/trace` 的分工：`/trace` 回答「刚才那轮发生了什么」（只管屏上能读的一屏，
会截断）；`/export` 回答「把这次会话留下来」，**内容不截断**——截断是显示层的事。
只有单条工具结果超过 8000 字符才截，且**显式标注被截了多少**（静默截断会让读
的人以为那就是全部）。

思考折叠进 `<details>`，内部事件（`agent/round` / `plan/updated`）不进导出。
**不放工作区**——与会话 / 检查点同一取舍，导出是工具产物，不该往代码仓库留垃圾。

### git 工具面
`git_status` / `git_diff`（只读）· `git_add` / `git_branch` / `git_stash`
（medium，默认不拦）· `git_commit`（high，走审批）。

**缺 `git_add` 曾经是条断路**：`/commit` 的提示词让模型「向用户说明并给出建议
（如先 git add 暂存）」，而模型想自己暂存只能走 `run_command`（`ToolRisk.high`），
于是每次提交都要弹一次审批框，例行步骤被推回给了用户。

三个写操作工具**都不提供丢数据的入口**（无 `reset --hard` / `clean` /
`switch -C` / `push --force`）——那些留给用户自己在终端里做。`git_add` 缺参时
报错而不是默认全量暂存，避免模型一次手滑把整个仓库扫进去。

## `!` 快捷 shell 与 lint-on-edit

- `!<命令>`：直接执行 shell 命令（**不进模型、不烧 token**），走沙箱缝；
  `!!` 重跑上一条。
- **shell 模式**（与 OpenCode 一致）：在**空提示符**打 `!` 进入 shell 模式——
  输入框前缀变 `!`（黄）、占位提示「输入 shell 命令，Esc 退出」、状态栏提示
  `[Enter] 执行 | [Esc] 退出`；`Esc` 不执行直接退出；执行完自动退出回对话模式
  （一次性）。shell 模式里 `/` 与 `@` 交给 shell 解释，不弹补全面板。
- lint-on-edit：模型编辑文件后自动跑 linter（`[lint]` 可配置：
  `enabled` / `command` 覆盖 / `debounce_seconds`），告警追加进工具结果
  当场闭环；按项目类型自动探测（pubspec→`dart analyze`、package.json→
  `eslint .`、go.mod→`go vet ./...`、Cargo.toml→`cargo check`）。

## Hooks（`[hooks]`）

config.toml `[hooks]` 表：`pre_tool_use`（任一非零退出即拒绝该工具）、
`post_tool_use`（失败追加提示）、`stop`（轮次收口，失败只提示）。hook 命令
经 `/bin/sh -c` 直连运行（**不走** `'shell'` 沙箱缝）；注入环境变量
`NAVA_HOOK_EVENT` / `NAVA_HOOK_TOOL` / `NAVA_HOOK_ARGS_JSON`。

```toml
[hooks]
pre_tool_use = ["echo 工具前钩子 >> /tmp/nava-hook.log"]
# post_tool_use = []
# stop = []
```

## MCP（`/mcp`）

`[mcp.servers.<名字>]` 表声明 MCP server，启动时逐台挂载、**单台连接失败提示并
跳过**（不阻塞启动）。工具以 `server__tool` 前缀进工具表（`/tools` 可见），
风险映射后按当前权限模式走审批；`/mcp` 查看已接入的 server（就绪状态 / 工具数）。

- `type`：`stdio`（本地子进程，`command` + `args`）/ `http` / `sse`（远程端点 `url`）。
- `env` / `headers` 支持 `${KEY}` 占位符，经凭据服务（`[credentials]` / 环境变量）
  解析；**解析结果不得写进日志**。
- **安全边界**：MCP server 是用户在配置里显式声明的受信端，其 stdio 子进程
  **不走** Layer 2 OS 沙箱（沙箱管的是模型临时写出的命令，二者风险面不同）。

## 模型提供商（`/provider` / `/model`）

提供商在 `~/.nava/config.toml` 的 `[providers.<名字>]` 表里定义
（实现 `lib/src/providers/`，公开入口 `lib/providers.dart`）；`[llm]
default_model = "provider/model"` 同时定当前提供商与默认模型。

- `/provider`：展示注册表；`/provider add` 或面板里 `[ Add New Platform ]`
  新增（表单只填 **base_url / model**，`name` 可选留空自动从 base_url 推导、
  `type` 固定 `openai`，写回 config.toml；**第一个** provider 会同时设为
  `default_model`）；删除与切换默认仍直接编辑 config.toml
- `/model`：打开当前提供商的模型选择浮层——候选优先取 config.toml 的
  `[models."<provider>/<model>"]` 清单（kimi 兼容格式；`/model <片段>` 预填搜索框，
  搜索过滤后 Enter 切换）；配置无清单时从 models.dev 拉取该 provider 的清单兜底
  （缓存 24h，失败仅展示配置内模型）；没有候选也照常打开浮层
- 未配置任何 provider 时启动进入引导：TUI 照常启动并自动弹出 provider 面板，
  模型调用会提示先用 `/provider` 添加或编辑 config.toml——**没有缺省回退链**
  （回退链需在 config.toml `[llm] fallback_models` 里显式声明）

```toml
[providers.my-gateway]
api_key = "sk-..."      # 可省略；空时构造期报缺凭据
base_url = "https://my-gateway.example/v1"   # OpenAI 兼容端点根地址（必填）
type = "openai"         # openai→chat/completions；kimi→responses（缺省 openai）
# [providers.my-gateway.oauth]   # 保留字段：OAuth 未实现，仅提示不可用
# key = "oauth-key-name"
```

- `type` 决定请求形态：`openai` 走 `chat/completions`，`kimi` 走 `responses`。
- `oauth` 子表：字段保留（`key`）但**不实现** OAuth 调用；配了 `oauth.key` 且
  未配 `api_key` 的提供商启动时提示不可用，其余照常。
- 以代码装配：`provideProviders(app, providers: <ProviderProfile>[...],
currentName: ..., credentials: ...)` 把注册表挂到 `'providers'` 服务，
  `registry.buildLlm(name, model: ...)` 按 profile 构造 OpenAI 兼容
  `LlmProvider`。Key 解析顺序：配置内 `apiKey` → 注入的凭据服务（缺省
  `EnvCredentials`）。

```dart
import 'package:conatus_code/providers.dart';

final ProviderRegistry registry = provideProviders(
  app,
  providers: <ProviderProfile>[
    const ProviderProfile(
      name: 'ark',
      baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    ),
  ],
  currentName: 'ark',
);
final LlmProvider? llm = registry.buildLlm('ark', model: 'doubao-seed-1-8-251228');
```

**Plan 端点只认订阅后生成的专属 Key**：`ark-agent-plan` 用
`ARK_AGENT_PLAN_API_KEY`、`volcengine-coding-plan` 用 `ARK_CODING_PLAN_API_KEY`，
普通方舟 Key（`ARK_API_KEY`）对 plan 端点会返回 401。

## LLM 韧性（重试 / 退避 / 回退链）

一次网络抖动不该让整轮失败。链路分两层，各自独立生效：

1. **退避重试**（同一提供商内）——限流（429）、5xx、超时、连接失败按指数退避
   重试，缺省 4 次 / 500ms 起翻倍 / 单次封顶 30s，带 ±25% 抖动。服务端给了
   `Retry-After` 就照它等。
2. **回退链**（换提供商）——上面重试耗尽后，按 `[llm] fallback_models` 换下一
   个候选。

只对**可重试**的错误重试：401 / 403、缺 API Key、400 这类重试无意义的失败一次
就上抛，直接进入回退（换一个 Key 正确的提供商才是出路）。

- 装配形状是两层嵌套：`FallbackLlm(RetryingLlm(主), RetryingLlm(备), …)`。
  先在原提供商上把能救的失败救回来，避免一次抖动就换模型、让回答风格在一次会话
  里来回跳。
- **流式重试只在尚未产出任何增量时生效**：已经 yield 出去的文本收不回来，静默
  重来只会让用户看到重复内容（回退链同理）。
- 配错的回退项（provider 不存在 / 重复）**跳过而不是整体失败**，并在 `/doctor`
  的「模型回退链」里列出；配错一条备用模型不该让主模型都用不了。
- 重试与回退都**实时上屏**（`· ark 触发限流，1.0s 后重试（2/4）`、
  `· ark 不可用，已切到 deepseek`）——退避可能静默 30 秒，没有提示在用户眼里
  就是卡死。`/doctor` 另报出候选链与最近一次回退。
- `/model` 切换主模型时**重建整条链**，回退项仍然跟随——否则一次切模型就顺手
  关掉了容错。

```toml
[llm]
default_model = "arkcli-agent-plan/doubao-seed-2-0-lite-260215"
fallback_models = ["deepseek/deepseek-chat", "openai/gpt-4o-mini"]
max_attempts = 4
```

框架侧（`conatus_llm`）的入口是 `RetryingLlm` / `RetryPolicy` / `LlmErrorKind`
与 `FallbackLlm`，任何宿主都能单独取用。

## 子 Agent（`spawn_agent`）

把一个自包含的子任务委托给隔离子 Agent（独立 `Session` + 受限工具白名单），
只把结论回传主链路。**每一步实时上屏**——子 Agent 一次能跑几十秒，屏上如果
完全静止就既判断不了它有没有跑偏，也不敢中途打断：

```
◆ 子 Agent：调研 checkpoint 存储的实现
  · 第 1 轮 思考中（工具已 0 次）
  → rg
  ✓ rg
  · 第 2 轮 输出 380 字符
  → read_file
  ✗ read_file
✓ 子 Agent success：3 轮 （rg、read_file）
```

（`TuiRole.stage` 暗色行，不污染助手正文的排版。）

**默认只读白名单**：不传 `tools` 时子 Agent 拿到 `get_time` / `echo` /
`read_file` / `rg` / `glob` / `list_files` / `git_status` / `git_diff`——够调研，
但不给写 / 执行类。显式传 `tools` 也**排除 high 风险**（双保险：写 / 执行类即便
被点名也要过审批）。

**工具调用复用宿主管线**：子注册表复制主注册表的守卫与环绕中间件，**审批、工具
结果驱逐、hooks / lint 对子 Agent 的工具调用同样生效**。所以子 Agent 读大文件也会
落盘成预览（不再把 20 万字符直接灌进子历史），写操作照样弹审批。

**历史照样压缩**：子 Agent 接上上下文的 `'compaction'`；配合上面的结果驱逐，长调研
不会顶爆模型窗口直接失败。

**独立预算**：子 Agent 用自己计数的 `BudgetedLlmProvider`，不共用主轮次的
token 额度——否则它那十几轮调用会把**主**轮次撞爆 `max_turn_tokens` 提前收口，
而子 Agent 的半截结论会被当成结论回传。成本仍记进同一个 costTracker（那部分
是真实花费）。

## 团队泳道（`/team`）

多 agent 的**实时总览**。每个成员一条泳道，边跑边显示它在调什么工具、说了什么：

```
◐ researcher  [执行中]
  · 第 1 轮
  → rg
  ✓ rg · 12 处匹配
  → read_file
  ✗ read_file
◆ swarm-1
  → read_file
  ✓ 收口：3 轮 （read_file、rg）
```

- `spawn_teammate` 起的成员与 `spawn_agent` 起的子 Agent **同处一个视图**
  （后者带 `swarm-` 前缀，标 `◆`）——两套委托机制语义不同但视图统一。
- 每条泳道保留最近 12 行（`kTeamLaneMaxLines`），连续正文会合并成一行，
  否则一条长回答就能刷掉整个泳道。
- `Esc` 或 `Ctrl+T` 返回对话。`Ctrl+T` 在对话视图下才是展开 TODO 列表。
- 任务板在泳道之后（没有任务时不渲染）。
- 状态栏显示团队人数 / 任务完成数 / 成本（成本取共用的 costTracker 真实费率）。

**已知边界**：泳道视图是**独占**的——切过去就没有对话区。若要「边看边聊」需要改
布局，那不是本次动的范围。

## 沙箱分层与已知边界

沙箱（`lib/src/sandbox/`）分两层，各自独立开关、独立失败语义：

- **Layer 1 · 应用层文件 jail**（`fs_jail`，默认开启）：
  `JailedFileSystem` 把 conatus `FileSystem` 接上 `dart_io_sandbox` 的 bound
  jail，读写限定在沙箱根内，越界映射为 `sandboxDenied`。纯应用层防误操作，
  **不依赖 OS 后端**，任何平台可用。
- **Layer 2 · OS 级沙箱**（`enabled`，默认开启，仅 macOS）：
  `CommandPolicy` 裁决命令形状（管道 / 重定向放行；`&&`、`;`、`$()` 触发
  review，TUI 内经人工复核裁决、headless 按拒绝），再由
  `SandboxedShellExecutor` 直调系统
  `/usr/bin/sandbox-exec` + 自建的 Seatbelt profile 执行：deny-default 基线、
  可写根经 `-D` 参数注入（工作区、/tmp 真实路径、常用 HOME 缓存、`writable_paths`），
  `/dev/null` 按字符设备放行，mach-lookup 收敛为系统服务白名单，最小环境变量、
  不继承父进程环境。设计对齐 OpenAI Codex CLI / Claude Code 的 seatbelt 方案。

**fail-closed 只作用于 Layer 2 后端**：sandbox-exec / Seatbelt 不可用时，
命令执行被拒斥执行器禁用（不降级为本地 shell），应用照常启动、Layer 1 文件
jail 继续生效。Layer 1 与 Layer 2 可独立关闭；`preset = "danger_full_access"`
显式关闭 OS 沙箱回本地直执（Layer 1 与命令策略仍生效）。

已知边界：

- `sandbox-exec` 在 macOS 上标记 deprecated 但系统自带可用；启动预检会 smoke
  试跑，失败时命令执行禁用（stderr 会提示，可在 config.toml 设
  `[sandbox] enabled = false` 关闭 Layer 2，保留 Layer 1 文件 jail）。
- 沙箱定位是防 LLM 乱跑命令的**护栏**：写默认限定在工作区 + 缓存目录，网络
  默认拒绝，读不限面（与 Codex / Claude Code 同姿态）；对抗决心攻击者不是其目标。
- mach-lookup 白名单是维护点：个别工具若因缺服务报错，按报错扩展
  `seatbeltMachAllowlist` 即可（TLS 所需的 trustd/ocspd 已内置）。
- CommandPolicy 的 REVIEW 已接线人工复核：TUI 内经选项浮层征询（NeverAsk
  视同放行），批准后在 seatbelt 内照常执行；headless 无浮层，REVIEW 仍按
  拒绝处理（fail-closed）。白名单/路径越界这类确定性违规不受复核豁免，
  优先按 deny 拒绝。
- Layer 2 仅支持 macOS：其他平台命令执行会禁用，请显式设
  `[sandbox] enabled = false`。

## 预算护栏

每轮（空闲 2 分钟视为新一轮）默认 10 分钟墙钟 + 上下文 token 护栏；
超限时模型收到收口提示而非直接报错。估算按约 4 字符 1 token 的粗口径
（`estimateMessagesTokens`），**只作护栏，不用于计费**。

**token 封顶跟模型窗口走**：已知窗口时取 `窗口 × 0.75`（余下 1/4 留给模型
输出与工具回填）与 `[budget] max_turn_tokens` 的较小者。此前是一个写死的
20 万——32k 窗口的模型永远等不到这条闸门（请求会先被 API 拒掉），1M 窗口的
模型又在 20% 处过早收口。窗口来自 models.dev（见下）。

## 成本与上下文窗口（models.dev）

models.dev 提供的**上下文窗口**与**真实单价**此前只用来填 `/model` 浮层的
候选表，两项都被丢掉。现由 `ModelProfileStore` 收成一份可查档案：

- **`/cost`**：按当前模型的真实费率算，输入/输出/缓存命中 token 分列，并
  讲清费率来源。**费率查不到就明说「未知」并按 0 计**——此前用的是两条写死
  的常数（$0.3/M in、$1.2/M out），对 DeepSeek 差一个量级、对 Gemini 差得
  更多，而用户看不出那个数字是编的。
- **状态栏 `ctx`**：分母是真实窗口。有一轮真实用量后，分子也换成接口返回的
  `prompt_tokens`（正是下一次请求要发的全部内容，含 system prompt、工具定义
  与工具结果），比按屏上记录 chars/4 猜准得多；首轮之前没有真实数据时前缀加
  `~` 表示是估算。
- **`/doctor`** 新增「模型窗口 / 费率」项。
- `/model` 切换后费率与窗口自动跟着换；provider 名对不上时按模型 id 跨
  provider 查（窗口与价格是模型属性）。

数据源离线且无缓存时全部显示「未知」，**不影响模型正常调用**。

## 开发

默认（独立使用）：`pubspec.yaml` 用 git 依赖引 conatus 仓库，clone 后直接
`dart pub get` 即可。

在 [conatus](https://github.com/Fi2zz/conatus) 仓库内开发时，本仓库作为 submodule
挂在 `packages/conatus_code`。该仓库的 `tool/setup_code_filter.sh` 会：

- 装一个 git clean/smudge filter，让 `pubspec.yaml` 里的 `resolution: workspace`
  在工作区保持生效 —— 本包成为 conatus pub workspace 的成员，依赖解析到本地
  `packages/*`，改框架对这里立即生效，不必先推送；而 `git add` 时该行会被自动
  注释掉，推送出去的内容因此不带 `resolution`；
- 生成一个本地 `pubspec_overrides.yaml`（已进 `.gitignore`），清空 `pubspec.yaml`
  的 `dependency_overrides` —— workspace 内禁止 override 成员包。

未装 filter 的 clone（例如直接 clone 本仓库）拿到的是注释态、且 override 原样生效，
行为与上面「独立使用」一致。

## 依赖

- [conatus](https://github.com/Fi2zz/conatus) — 框架
- Dart 3.6+；在 conatus 仓库内开发时需 3.11+（workspace 的 glob 语法要求）

## 与 conatus 的关系

conatus_code 是 conatus 的**上层应用**，不是框架的一部分。框架提供 Agent Loop、
工具系统、技能沉淀等底座；coding 相关能力（终端 UI、文件工具、代码执行）原为
`conatus_tui` / `conatus_fs_tools` / `conatus_coding` 三个独立包，**现已并入本包**，
入口分别为 `lib/tui.dart` / `lib/fs_tools.dart` / `lib/coding.dart`。本包负责装配
这些能力并暴露终端界面。

## CI

`.github/workflows/test.yml` 在每次 push / PR 跑：静态检查（`--fatal-infos`）
→ 全部测试 → 打包二进制。跑在 `macos-latest`——沙箱 Layer 2 只在 macOS 可用，
`test/sandbox/` 下两个测试文件没有跳过保护，放到 ubuntu 上要么必红、要么被迫
跳过最有价值的那批。

CI 验的是**独立形态**：checkout 拿到的是提交态 pubspec（`resolution: workspace`
被 git filter 注释掉，依赖经 git 拉 conatus master），也就是「用户 clone 本仓库
后拿到的东西」。conatus 工作区内的跨仓集成由 conatus 仓库的 CI 负责。

本仓库的 lint 规则因此**自包含**在 `analysis_options.yaml`（不像兄弟包那样
`include ../../analysis_options.yaml`）——独立形态下那个路径不存在。规则与
conatus 仓库根保持一致，改一处请同步另一处。

## 许可证

MIT
