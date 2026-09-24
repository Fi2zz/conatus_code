# Nava

> A terminal coding agent built on the conatus runtime.

## 是什么

基于 [conatus](https://github.com/Fi2zz/conatus) 构建的终端编码智能体。
复用 conatus 的 Agent Loop、工具系统、技能沉淀，
专注 coding 场景。

## 特性

- 🖥️ 终端交互（基于 conatus_tui）
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
# ignore = ["node_modules", "build/"]   # 额外忽略的相对路径前缀

[background]
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
文件**（`<项目数据目录>/checkpoints/<会话>/<sha256 哈希名>`——**文件名不可读、
无 `.gz` 扩展名、不暴露轮次时间线**，轮次只记录在归档头与会话级 gzip `index`
里；内容非明文、不保留目录结构；`dart:io` 内置 GZipCodec 自定义容器格式，零新
依赖；旧版目录树检查点读时兼容、索引缺失自动重建）。清单记录快照时刻的对话
切点事件 id。`/rewind [N]` 把工作区恢复到 N 轮前（缺省 1）的文件状态，**并同步
把对话回滚到该轮**：从切点事件 `Session.fork` 出新会话（append-only 不变式，
旧会话保留为记录），`/rewind list` 查看本会话可用检查点。快照/恢复走应用级
dart:io，不受 fs jail 约束；`/rewind` 是用户命令，不挂审批。

- 快照时机：会话绑定（turn 0）+ 每轮收口后；保留 base + 最近 `keep-1` 个差量。
- 恢复语义：base 铺底 + 差量覆盖/删除 + 删当前多余（rsync 式）。
- 变化检测：相对 base 的 mtime+size + SHA-256 哈希（stat 相同也兜底）。
- 对话切点：`lastEventId` 为 null（全新会话的 turn 0）时切到全新空会话。
- 关闭：`[checkpoint] enabled = false`（/rewind 提示不可用）。

## 后台任务（`/background`）

`run_command_background` 在沙箱中后台启动命令（不阻塞对话），返回 `bg-<n>`；
`list_background_tasks` / `background_output` / `background_kill` 管理之。
`/background [list|output <id>|kill <id>]` 是用户侧入口。任务走 `'shell'` 缝的
`start()`，照常受沙箱 CommandPolicy 裁决；并发上限读 `[background]
max_running_tasks`（缺省 4）；任务随进程退出而结束（`keep_alive_on_exit`
未实现）。

## 消息队列

busy 时输入不再被拒：自动排队（上限 20 条），当前轮收口后依次投递；`Esc`
打断会**清空队列**并提示条数；切换会话同样清空。cron/提醒的投递不受影响
（busy 时仍由调度器重试）。

## `/commit` 与 `/doctor`

- `/commit`：让模型查看 `git_diff --staged` 的暂存差异、写 Conventional
  Commits 提交信息，并经 `git_commit` 工具提交（high 风险走审批）。
- `/doctor`：体检——配置 / 提供商 / 沙箱（Layer 1/2）/ 工具表 / MCP / rg
  逐项 ✓/✗ + 修复提示，自查用。

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

## 沙箱分层与已知边界

沙箱（`lib/src/sandbox/`）分两层，各自独立开关、独立失败语义：

- **Layer 1 · 应用层文件 jail**（`fs_jail`，默认开启）：
  `JailedFileSystem` 把 conatus `FileSystem` 接上 `dart_io_sandbox` 的 bound
  jail，读写限定在沙箱根内，越界映射为 `sandboxDenied`。纯应用层防误操作，
  **不依赖 OS 后端**，任何平台可用。
- **Layer 2 · OS 级沙箱**（`enabled`，默认开启，仅 macOS）：
  `CommandPolicy` 裁决命令形状（管道 / 重定向放行；`&&`、`;`、`$()` 触发
  review，当前按拒绝处理），再由 `SandboxedShellExecutor` 直调系统
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
- 审批判定 `REVIEW` 目前按拒绝处理（不启动进程），"REVIEW → 人工审批"
  未接线。
- Layer 2 仅支持 macOS：其他平台命令执行会禁用，请显式设
  `[sandbox] enabled = false`。

## 预算护栏

每轮（空闲 2 分钟视为新一轮）默认 10 分钟墙钟 + 20 万估算 token 护栏；
超限时模型收到收口提示而非直接报错。估算按约 4 字符 1 token 的粗口径
（`estimateMessagesTokens`），**只作护栏，不用于计费**。成本跟踪
（`CostTrackerImpl`）按用量与粗略单价累计 `todayCost`，供自主运行
（`provideAutonomous`）的预算检查消费。上限可用 `[budget]` 配置，或
`ConatusTuiRuntime.create(turnBudget: TurnBudget(maxDuration: null, maxTokens: null))`
关闭。

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

conatus_code 是 conatus 的**上层应用**，不是框架的一部分。
coding 相关的能力（文件工具、代码执行）在 conatus 的
[conatus_fs_tools](https://github.com/Fi2zz/conatus/tree/master/packages/conatus_fs_tools)
和 conatus_coding 包里，conatus_code 负责装配它们并暴露终端界面。

## 许可证

MIT
