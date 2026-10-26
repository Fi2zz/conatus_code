# Nava

> A terminal coding agent built on the conatus runtime.

## 是什么

基于 [conatus](https://github.com/Fi2zz/conatus) 构建的终端编码智能体。
复用 conatus 的 Agent Loop、工具系统、技能沉淀，
专注 coding 场景。

## 特性

- 🖥️ 终端交互（内置 TUI，入口 `lib/tui.dart`；Enter 提交，Shift+Enter / Ctrl+J 换行）
- 🔍 文件读写与搜索（read_file / write_file / edit_file / rg / glob；read_file 支持 png/jpg/gif/webp 图片与 PDF 附件）
- 🧠 技能沉淀（重复轨迹自动抽象为可复用工具）
- 🤝 多智能体协作（任务板 + 成员运行时）
- 🔒 审批与沙箱（高危操作走审批；默认 Seatbelt 进程沙箱 + 文件 jail）
- 🗺️ 计划闭环（plan_write 建计划、update_plan 执行中推进、计划面板实时渲染）
- 🩹 失败自愈（工具失败自动反思重试，可按需重规划）
- ⏱️ 预算护栏（每轮墙钟 + 上下文 token 估算 + 成本跟踪）
- 📜 故事层（可选，默认关闭）：编辑即补丁、事前审阅、`/story` 时间轴与分叉

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

注意：OS 沙箱后端（launcher）仍在运行时从 pub 缓存定位，换机器或清理 pub
缓存后沙箱会 fail-closed（命令执行被禁用，文件 jail 保留），这与源码运行
时的行为一致。

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
# subagent_permission = "inherit"  # 子代理默认权限：inherit/readonly/ask/auto（模型只能收紧）
# project_dir = ".conatus"    # 项目数据目录（会话/记忆/数据库/检查点）；缺省不放工作区，
                              # 落 ~/.nava/projects/<编码工作区路径>；显式设置才
                              # 相对工作目录（旧行为，工作区会出现该目录）。
                              # 不允许指向 .opencode / ~/.config/opencode（只读），
                              # 否则回落到缺省目录并在 stderr 提示

[approval]
mode = "ask_when_needed"      # always_ask / ask_when_needed / never_ask

# 权限规则：最外层工具中间件（先于审批 / hooks / lint / story）。按 action +
# resource 通配匹配，后出现的规则优先，任一条 deny 即拒绝。省略则只有兜底阈值。
# 动作：read / edit / glob / grep / shell / websearch / webfetch / subagent /
# skill / question / external_directory，也可直接写工具名（装配时归一，
# run_command→shell、read_file→read、rg→grep）。
# 路径动作的资源按工作目录解析，符号链接按真实路径比较。
# [[permissions]]
# action = "shell"
# resource = "git push *"
# effect = "deny"
#
# [[permissions]]
# action = "external_directory"
# resource = "~/shared/*"
# effect = "ask"

# [formatter]
# command = "dart format"     # 覆盖自动探测；$FILE 占位符可选
# extensions = [".dart"]
# timeout_ms = 10000

[story]
# enabled = false             # 人机双写故事层（可选）：开启后写工具先成待定补丁，
                              # /story 查看时间轴并 apply/reject；见 docs/story.md

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

已废弃但兼容的键（`[thinking]`、`[services]`、`[loop_control]`、
`default_plan_mode`、`telemetry`，以及 `[models.*]` 的
`max_output_size` / `reasoning_key` / `support_efforts` / `default_effort` /
`off_effort` / `protocol` / `base_url`）仍会被接受，但载入时只写入告警；
启动提示与 `/doctor` 的“配置废弃项”会列出来，不再静默 no-op。

## 从 OpenCode 导入配置（`nava import opencode`）

nava **不会在启动时自动合并**项目 `opencode.json(c)`：项目文件可以声明 MCP
命令与权限，自动生效等于克隆一个仓库就能拉起进程或改写工具权限。需要迁移时
显式运行：

```bash
nava import opencode                 # dry-run：打印将新增的 TOML 片段
nava import opencode --write         # 原子写入 ~/.nava/config.toml
nava import opencode --project-only  # 只读项目 / 祖先目录
nava import opencode --global-only   # 只读 ~/.config/opencode
```

- 读取全局 `~/.config/opencode/opencode.json(c)` 与项目祖先的
  `opencode.json(c)` / `.opencode/opencode.json(c)`，顺序与 OpenCode 一致
  （全局 → 项目直接配置 → `.opencode`，后者覆盖前者）。
- 映射：`model`（去掉不支持的 `#variant`）、`default_agent`、`mcp.servers`
  （local / remote、`environment` / `headers` / `oauth`、`{env:NAME}` 占位符）、
  `permissions`（OpenCode 动作名归一为 nava 动作）、`instructions`、
  `skills`（本地目录 → `extra_skill_dirs`，HTTP catalog 告警跳过）。
- **JSON agents / commands 物化为 Markdown**：`agents.<id>` 写到
  `~/.nava/agents/<id>.md`（全局）或 `<workdir>/.nava/agents/<id>.md`（项目），
  `commands.<name>` 同理写到 `.nava/commands/`；现有 Agent / Command 注册表
  直接发现，不需要新的运行时接口。已有同名文件不覆盖。
- **不覆盖已有配置**：已有 `default_model` / `default_agent` / 同名 MCP /
  重复 permission 会跳过；顶层 `instructions` / `extra_skill_dirs` 已存在时
  整项跳过（不合并数组）。
- `providers` / `plugins` / `lsp` / `references` / `policies` / `formatter` /
  `tools` 暂不支持，逐项告警。
- `--write` 走 `writeConfigFile`：原子写、权限 0600；写入前先校验合并结果仍是
  合法 TOML。

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
- 接管已有会话（`--continue` / `--session`）时，nava 关闭期间在外部做的编辑
  不在任何快照里；`/rewind` 只回滚到已记录的轮次，执行前请确认工作区状态
  （撤销前会弹确认，但确认文案只能统计快照之间记录到的改动）。

### 按轮撤销与重做（`/undo` / `/redo`）

`/undo [N]`（缺省 1 轮）撤销工作区**和**对话：先恢复文件到该轮检查点，再按
`lastEventId` fork 会话切过去，并把被撤回的最新一条用户 prompt 回填到输入框
（`/undo 2` 这类多轮撤销另有系统行说明其余 prompt 未回填）。撤销点留在内存
里，`/redo` 恢复撤销前的文件并切回原会话；发下一条 prompt 即视为提交，撤销点
作废。与 `/rewind` 的差别：`/rewind` 是一次性回滚、不能重做。

- `/undo` 与 `/redo` **都会先确认**：恢复是 rsync 语义，撤销后新建 / 修改的
  文件在重做时会被删除或覆盖，所以在动工作区之前弹一次确认。
- 撤销点只在撤销后切过去的会话里有效：显式切会话（`/session`、会话面板、
  `/new`）或 `/rewind` 会清掉它；之后 `/redo` 会提示没有可重做的回滚（不会自动切回原会话）。
- `[checkpoint] enabled = false`：只回滚对话（按 user/message 事件推算轮次边界），
  文件不动，并提示「checkpoint 已关闭」。
- 轮次不够（`/undo N` 超过当前轮次或 prompt 数）或目标轮次已被 `keep` 裁剪：
  明确报错，不做任何改动（不静默夹到第 0 轮）。
- 有在途轮次时 `/undo`、`/redo` 与切会话一律拒绝。

## 差异查看（`/diff`）

`/diff [working|turn]`（缺省 `working`）打开只读的交互式差异视图：

- `working`：工作区 git 差异 + 未跟踪文件（不在 git 仓库时回落到本轮检查点）；
  工作目录取 `[agent] workdir`，不是进程 cwd。
- `turn`：本轮检查点 vs 上一轮；两侧内容各批量读一次（归档只解压 base /
  差量各一遍）。第 0 轮没有「上一轮」，显示「还没有可比较的轮次」而不是把
  整个基线当成新增文件。
- 视图内 `m` 标记已读、`d` 切换范围、`j/k` 滚动、`q` 关闭；不写工作区、
  不动检查点。`.opencode` / 凭据 / `build` 等排除面与检查点同源。

## 权限规则（`[[permissions]]`）

权限中间件挂在根上下文**最外层**：hooks、结果驱逐、lint、story 审阅只能看到
被放行的调用。规则来源按 `config → project → session` 拼接（后者覆盖前者），
任意一条 `deny` 即拒绝，`ask` 走审批浮层，`allow` 直接执行。

- **动作归一**：`read_file`→`read`、`write_file`/`edit_file`/`apply_patch`→
  `edit`、`run_command`/`run_tests`/`run_code` 与四个 git 写工具
  （`git_add`/`git_commit`/`git_branch`/`git_stash`）→`shell`、`rg`→`grep`。
  git 写工具的资源由实际 argv 派生（`git add ...`），所以 `action = "shell"`,
  `resource = "git *"` 能拦住它们；`runGit` 另有一道 `.opencode` 写保护。
- **路径匹配**：规则资源与调用路径都按工作目录解析，并补真实路径拼写
  （符号链接按目标身份比较）。`edit "src/*"` 能拦住
  `write_file("/abs/work/src/x")`，工作区里指向 `/etc/hosts` 的链接也逃不过
  `deny read "/etc/*"`。
- **工作区外**：路径落到 workdir 外时追加 `external_directory` 判定；`rg` 的
  `path` 参数也参与边界检查（但不会把每次 rg 变成路径信任提示）。
- **MCP 资源**：`action = "list_mcp_resources"` / `"read_mcp_resource"` 配合
  `resource = "<server>"` / `"<server>:*"` 可只放行单台；旧式
  `action = "<server>_list_mcp_resources"` / `"<server>_read_mcp_resource"`
  仍会与现行动作同时判定（取更严格者）。
- **持久化**：交互里「总是允许」写进项目数据目录的 `permissions.json`；若会
  覆盖已有 deny（含「更具体的 deny」如 `git push origin *` 对上 `git push *`）
  则拒绝落盘，仅本次会话放行。
- **损坏文件**：沿用 fail-open（Agent 仍能启动），但载入错误会写进系统提示与
  `/doctor`；单条坏规则被跳过并计数上报。

## `.opencode` 只读

`.opencode/**`（项目级）与 `~/.config/opencode/**`（全局）是用户自己 OpenCode
的安装：nava 只做兼容读取，**绝不创建 / 写入 / 删除 / 改权限**。

- fs 工具（`write_file` / `edit_file` / `apply_patch` / story 写回）经 `'fs'`
  接缝上的只读闸门拦截；删除工作区的祖先目录也会被拒（否则会连带删掉
  `.opencode`）。
- 检查点默认排除 `.opencode` 与 `.config/opencode`，恢复不会把它们写回。
- **配置与令牌写入同一道闸门**：`--config .opencode/config.toml`、
  `NAVA_HOME=.opencode`、父目录符号链接指向 `.opencode` 都在创建文件之前拒绝；
  `~/.nava/oauth` 在派生阶段就校验，令牌绝不会落到只读目录。
- 命令侧（`run_command` / git 写工具）有字面识别兜底：**best-effort**，不是
  安全边界；变量拼接、`sh -c`、读脚本再执行都能绕过。真正的边界是 Seatbelt
  （`deny file-write*`），sandbox 关闭时请自行确认风险。

## 人机双写故事层（可选）

`[story] enabled = true` 时，`write_file` / `edit_file` / `apply_patch` 不再直接
落盘：先登记为**待定补丁**，用 `/story pending` 查看、`/story apply <i>` 接受、
`/story reject <i>` 丢弃。人的直接编辑也会被登记为补丁，AI 在下一轮请求前收到
「改了哪些文件」的摘要通报。`/story` 是补丁时间轴，支持 `preview` / `discard` /
`fork`。

默认关闭，关闭时行为与普通编码会话完全一致。数据落在
`~/.nava/projects/<编码工作区路径>/story-log/`。完整语义、冲突处理与已知边界见
[docs/story.md](docs/story.md)。

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

## 标签、主题、键位与扩展

**会话标签**：每个标签是一个独立会话（JSONL + 检查点 + 权限模式 + Agent）。
`ctrl+tab` / `ctrl+shift+tab` 切换，`<leader>w` 关闭（只移除视图，不删数据）；
上限 8 个，标签栏的切换 / 关闭提示取自当前 keymap。`/new` 新会话使用
`[agent] default_agent`，不继承上一个标签的 Agent——切回旧标签会恢复它自己的
`agent/selected` 记录。

**主题**：`/theme` 切换 `default` / `dark` / `light` / `tokyonight`（仅当前进程）；
也可在 `[tui]` 写 `theme` 与 `animations`。

**键位**：`[keybinds]` 按动作 ID 覆盖，`<leader>` 是两段式前缀，`none` 关闭动作：

```toml
[keybinds]
leader = "ctrl+x"
"app.exit" = "ctrl+c,ctrl+d"
"session.new" = "<leader>n"
"tab.next" = "ctrl+tab"
"tab.close" = "<leader>w"
```

`/keybinds` 展示当前生效值与冲突告警；未知动作 / 非法键位会在启动时提示。

**自定义命令**：`.opencode/commands/**/*.md`（只读兼容）与
`.nava/commands/**/*.md`（项目 / 全局）发现为 `/<相对路径>`。正文是 prompt，
`$ARGUMENTS` 展开完整参数，`$1..$9` 按位置取参且**最高位吃掉剩余 token**
（与 OpenCode 一致）；`` !`命令` `` 块先执行再把输出插进提示词。frontmatter
支持 `agent:`、`model:` 与
`subagent: true`（前台跑 `spawn_agent`，命令与结果作为 `user/message` /
`tool/result` 进会话）。`subagent: true` 的 `model:` 不生效（模型由 agent 定义
决定），会明确提示。

**自定义 Agent**：`.opencode/agents/**/*.md` 与 `.nava/agents/**/*.md`；同名覆盖
内置 `build` / `plan` / `general` / `explore`。frontmatter 支持 `mode`
（`primary` / `subagent` / `all`）、`model`、`steps`、`tools` 白名单 / 开关、
V2 的 `permissions` 数组与 V1 的 `permission` 映射；OpenCode 工具名会归一
（`question`→`ask_user`、`todowrite`→`update_plan` 等）。`[agent] default_agent`
决定新会话默认值。内置 `general` 显式列出
可写工具白名单（read / write / edit / git 读写 / web），但 high 风险工具
（`run_command`、`run_tests`、`git_commit`）与 `spawn_agent` 仍被框架挡在子
Agent 之外。

**技能发现**：项目 `.conatus/skills` → `.opencode/skills` → `.agents/skills` →
`.claude/skills`，用户 `~/.nava/skills` → `~/.config/opencode/skills` →
`~/.agents/skills` → `~/.claude/skills`；同名由前者胜出。OpenCode / Claude
的技能目录无需软链即可直接读取。顶层 `extra_skill_dirs` 可追加额外目录
（相对 workdir / 绝对路径 / `~`）；`merge_all_available_skills = true` 会把
`disable-model-invocation` 的技能也放进模型可见目录（缺省 `false`）。

**定义热重载**：`.nava` / `.opencode` 的 `agents/`、`commands/` 目录发生变更
后，会在 250ms 防抖后自动重载；也可 `/reload` 手动触发。当前 Agent 被删除时
回退到 `[agent] default_agent`；配置文件变更仍需重启 nava（避免半套服务重建）。

**MCP CLI**：`nava mcp add <名字> --url <http(s) 地址>` / `-- <命令...>`、
`list`、`auth`、`logout`；`--config` / `NAVA_HOME` 可覆盖配置位置。写路径统一
经 `.opencode` 只读闸门（字面路径、`NAVA_HOME`、符号链接父目录都拒绝，见下节）。

## `/commit` 与 `/doctor`

- `/commit`：完整提交流程——`git_status` 看未暂存的 → `git_add` 暂存 →
  `git_diff --staged` 复核 → 写 Conventional Commits 提交信息 → `git_commit`
  提交（high 风险走审批）。
- `/review`：审查当前未提交改动（命名/边界/安全/性能，**只审不改**），
  提交/提 PR 前自检。
- `/doctor`：体检——配置 / 提供商 / 回退链 / 模型窗口与费率 / 沙箱（Layer 1/2）/
  工具表 / MCP / Agent 与命令发现（坏文件、未知 Agent `model:`）/ rg 逐项
  ✓/✗ + 修复提示，自查用；发现告警启动时也会上屏（前 5 条）。

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

## 代码检索（XERJ，可选）

[XERJ](https://xerj.org) 是一个本地检索二进制：索引一次源码后，按「定义优先」返回
`file:line` + 片段，比 `rg` 少读很多上下文。它是**可选外部依赖**——PATH 上没有
`xerj` 时三个工具都不注册，nava 的行为与接入前完全一致。

```bash
curl -fsSL https://xerj.org/get | sh    # 装 xerj（不装也能用 nava）
```

| 工具 | 用途 |
|------|------|
| `code_search` | 自然语言/关键词检索，返回定义与片段 |
| `find_definition` | 已知符号名时定位定义与签名 |
| `index_project` | 为当前项目建/刷新索引（幂等、可续跑） |

首次使用先 `index_project`。之后 `write_file` / `edit_file` / `apply_patch` 成功后，
会在 20 秒静默期后于后台增量刷新一次（同一时间只跑一个；项目必须先成功索引过一次，
避免首次使用时突然全量索引）。想关掉设 `auto_index = false`。节点由 nava 懒启动在 `127.0.0.1:19200`，同时占用
`19201`（XERJ 的 native REST），数据目录 `~/.nava/xerj`（不在工作区内），退出时只停止
自己启动的节点。索引前缀按工作区哈希派生，多个项目共用同一节点也不会互相污染。

默认 embedder 是**词法哈希**而非神经语义；索引时关闭 semantic 与 graph
（`--no-semantic --no-graph`），更快更小。检索走本地节点，数据不出本机。命令统一带
`--disable-feedback`。XERJ 不在模型命令沙箱的可执行白名单里，适配层直接经本地
shell 执行它（参数由适配层拼装，`index_project` 的路径限制在工作区内）。

```toml
[xerj]
enabled = true
url = "http://127.0.0.1:19200"
# data_dir = "~/.nava/xerj"
# prefix = ""              # 留空 = 按工作区派生
# auto_index = true        # 编辑后后台增量刷新
```

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
- format-on-edit：`[formatter]` 表存在时启用（`enabled` 缺省 true；
  `command` / `timeout_ms` / `extensions` 可覆盖），编辑成功后先格式化再交给
  linter；探测 pubspec→`dart format`、go.mod→`gofmt -w`、Cargo.toml→`rustfmt`、
  package.json 含 prettier→`prettier --write`、pyproject 含 `[tool.ruff]`→
  `ruff format`。表缺失时完全不启用；失败 / 超时 / 沙箱白名单拒绝只追加
  `[Formatter] skipped` 提示，不影响工具成功。一次编辑涉及超过 20 个文件时只
  格式化前 20 个，其余在提示里报数量（整批跳过会让大补丁带来的文件全不格式化）。

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
- **项目根 `.mcp.json` 直接兼容**：Claude Code / OpenCode 生态的 `mcpServers`
  形状会被读取并映射成同样的声明（`command` / `args` / `env` / `url` /
  `headers` / `oauth`）；同名 `[mcp.servers.*]` 优先，坏条目只告警跳过，
  `nava mcp list` 与 `/mcp` 都会包含它们。`.mcp.json` 是**项目文件**，stdio
  子进程不经沙箱，启动时会提示来源——只在你信任该仓库时使用。
- 远程 server **缺省尝试 OAuth**：令牌存 `~/.nava/oauth/<server>.json`（文件 0600、
  目录 0700，含 DCR `client_id` 以便新进程刷新），过期前 60 秒自动刷新；没有令牌
  时先按未鉴权连接，服务端真返回 401 才标记 `needs_auth` 并只跳过该 server。
- `oauth = false` 关闭 OAuth；已配置静态 `headers.Authorization` 的 server 默认
  不要求 OAuth（显式 `[mcp.servers.<名字>.oauth] enabled = true` 可覆盖）。
  `nava mcp auth <名字>` 登录，`nava mcp logout <名字>` 删除令牌；
  `nava mcp add <名字> --url <http(s) 地址>` / `-- <命令...>` 写配置（非 http(s)
  地址拒绝），`nava mcp list` 只读列出。刷新令牌不轮换时保留旧
  `refresh_token`；401 先重读令牌文件，别的 nava 进程已刷新就直接复用。
- `env` / `headers` 支持 `${KEY}` 占位符，经凭据服务（`[credentials]` / 环境变量）
  解析；**解析结果不得写进日志**。
- **安全边界**：MCP server 是用户在配置里显式声明的受信端，其 stdio 子进程
  **不走** Layer 2 OS 沙箱（沙箱管的是模型临时写出的命令，二者风险面不同）。
- 接入第三方插件（Markdown 技能包 / MCP server / CLI 脚本 / 纯库）的分档指南：
  [docs/plugin-integration.md](docs/plugin-integration.md)。

## 声明式自定义工具（`[[tools]]`）

nava 是 AOT 二进制，**不运行 OpenCode / Claude 的 JS 插件**。要把自定义工具接进来，
用声明式 `[[tools]]` 把它包成 CLI 子进程或 HTTP 端点——脚本本身可以是 Node、Python、
Go、shell，只要能读写 JSON。

```toml
[[tools]]
name = "deploy"
description = "Deploy a service to an environment"
command = "node"
args = ["tools/deploy.mjs"]
risk = "high"             # low / medium / high；缺省 high
timeout_ms = 30000
cwd = "tools"             # 相对 [agent] workdir
env = { TOKEN = "${TOKEN}" }

[[tools.params]]
name = "environment"
type = "string"           # string / integer / number / boolean / enum
required = true
description = "target environment"
```

- **CLI 协议**：模型参数以 `{"name":"deploy","arguments":{...}}` 从 stdin 传入；
  stdout 返回 `{"content":"..."}`、`{"error":{"code":"...","message":"..."}}`、
  `{"value":...}` 或纯文本。非零退出码 → `TOOL_EXIT`，超时 → `TOOL_TIMEOUT`。
- **HTTP 协议**：同样的 JSON 作为请求体发到 `url`（`method` 缺省 `POST`），
  2xx 响应按同一条输出协议解析；非 2xx → `TOOL_HTTP`。`headers` / `env`
  支持 `${KEY}` 凭据占位符。
- **参数 schema** 用 `[[tools.params]]` 显式声明，模型据此调用；支持
  `string` / `integer` / `number` / `boolean` / `enum`。
- **安全**：自定义工具是用户显式配置的受信端，CLI 子进程**不走** Layer 2 沙箱，
  HTTP 请求也不受命令沙箱约束；缺省 `high` 风险，走审批。只接你信任的脚本/端点。
- OpenCode 插件里的 `ctx.tool.transform` 自定义工具无法自动转换；把它的入口
  写成 CLI（读 stdin JSON、写 stdout JSON）或用 MCP 包装即可复用。

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

- `type` 决定请求形态：`openai` 走 `chat/completions`，`kimi` 走 `responses`，
  `anthropic` 走 Anthropic Messages（`/messages`）。
- `oauth` 子表：字段保留（`key`）但**不实现** OAuth 调用；配了 `oauth.key` 且
  未配 `api_key` 的提供商启动时提示不可用，其余照常。

### OpenCode Go / Console

OpenCode 的推理网关兼容 OpenAI，但 **Go 计划要求每个会话带稳定的

```http
x-opencode-session: ses_...
```

nava 绑定会话后自动把 `session_<uuid>` 映射成 `ses_<uuid>` 并随每个请求发送
（仅 `opencode.ai` 主机自动启用；代理/镜像可用 `session_header` 覆盖头名）。
默认 User-Agent 为 `nava/0.1.0`，也可以按 provider 覆盖。

```toml
[llm]
default_model = "opencode-go/glm-5.3"

[providers.opencode-go]
api_key = "oc_sk_..."        # https://opencode.ai/console 生成
base_url = "https://opencode.ai/inference/go/openai/v1"   # Go
# Pay-as-you-go 用：https://opencode.ai/inference/openai/v1
type = "openai"              # GPT 系模型用 kimi（responses）
# session_header = "x-opencode-session"   # 缺省按 opencode.ai 自动启用
# user_agent = "nava/0.1.0"
```

- 端点必须带 `/openai/v1` 后缀（chat 走 `/chat/completions`，responses 走
  `/responses`）；旧的 `opencode.ai/zen/go/v1` 已不可用。
- Go 里走 Anthropic Messages 的模型（Claude Haiku、MiniMax M3、Qwen3.8 等）
  用 `type = "anthropic"` 接入：

```toml
[providers.opencode-go-anthropic]
api_key = "oc_sk_..."
base_url = "https://opencode.ai/inference/go/anthropic/v1"
type = "anthropic"
# session_header / user_agent 同上，可省略
```

- 直连 Anthropic 用 `base_url = "https://api.anthropic.com/v1"`、`type = "anthropic"`；
  nava 会自动按主机选择认证头（`opencode.ai` 用 Bearer，其它主机用 `x-api-key`）。
- `/provider add` 的预设有 `opencode-go` / `opencode-console`（OpenAI 兼容）与
  `opencode-go-anthropic` / `opencode-console-anthropic`（Anthropic Messages）；
  网关不在 models.dev 里时，预设会写入内置模型清单供选择。
- Anthropic 的 prompt caching 默认启用：`cacheable` 的 system 前缀与最后一个工具
  自动带 `cache_control: ephemeral`；thinking 块的 signature 会随会话事件保留，
  在 tool loop 的下一轮请求里回传。

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
`ARK_AGENT_PLAN_API_KEY`、`volcengine-coding-plan` 用
`ARK_CODING_PLAN_API_KEY`，普通方舟 Key（`ARK_API_KEY`）对 plan 端点
会返回 401。

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

**权限模式（`permissionMode`）**：子代理级策略，对齐 Claude Code。宿主在
`[agent] subagent_permission` 设默认（`inherit` / `readonly` / `ask` / `auto`），
模型可在
`spawn_agent` 的 `permission_mode` 请求，但**只能收紧**：

- `inherit`（默认）：走宿主同一条审批管线。
- `readonly`：仅 low 风险工具，medium/high 直接拒（不弹审批）。
- `ask`：每个子工具调用都要确认（阈值 low）。
- `auto`：子调用免审批（仍在 Layer 2 沙箱内；high 工具仍被白名单风险上限挡掉）。

无审批人时（headless 不装审批服务）`ask` **退化为只读**：写 / 执行类拒绝，低风险
读取照常，而不是把所有子工具静默拒掉。

**Esc 打断会收掉在跑子 Agent**：子 Agent 跑在自己的 `Session`、不参与主轮次的取消
竞速，`Esc` 只丢主轮次结果的话它会在后台继续烧 token；现在 `Esc` 一并把在途子
Agent 取消，收敛为 `status=failed`。

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
- `Ctrl+Tab` / `Ctrl+Shift+Tab` 切换会话标签（`<leader>w` 关闭当前标签）；
  团队视图用 `/team` 进入——`Ctrl+Tab` 不再切视图。
- 任务板在泳道之后（没有任务时不渲染）。
- 状态栏显示团队人数 / 任务完成数 / 成本（成本取共用的 costTracker 真实费率）。

**已知边界**：泳道视图是**独占**的——切过去就没有对话区。若要「边看边聊」需要改
布局，那不是本次动的范围。

## harness（可选）

`nava harness` 管理可版本化的 harness 制品（`HarnessManifest`）：指令段、执行档位
（推理强度 + 工具预算）与工具边界，由 `conatus_harness` 装配成一棵可回滚的
Context 子树。

```bash
nava harness list ./harnesses          # 列出目录下的 manifest
nava harness show harnesses/std.json   # 规范化 JSON（键顺序稳定）
nava harness diff a.json b.json        # 人可读差异
nava harness check harnesses/std.json  # 校验，可用于 CI
nava --harness harnesses/std.json      # 本次运行装配（TUI 与 -p 共用）
```

**注意**：`allowedTools` 非 `null` 时白名单外工具会被拒（`TOOL_NOT_IN_HARNESS`），
这是真实限制而不是提示；先用 `allowedTools: null` 只切指令段与预算更安全。
`reasoningEffort` 只是声明——当前由 harness 记录，宿主仍未按档位改 provider 选项。

## headless（`-p`）与安全姿态

`nava -p <任务>` 跑**无人值守的单轮**：装配完整运行时（工具 / 沙箱 / MCP /
预算）但不启动 TUI，输出回复即退出（`--output-format text|json`）。

**权限在 headless 下仍然生效**：权限中间件照常挂在最外层，只是没有审批人。
`[approval] mode` 直接落到兜底阈值：

- `ask_when_needed`（缺省）：阈值 `high`——`run_command` / `apply_patch` /
  `git_commit` 这类工具需要确认，于是返回 `PERMISSION_ASK_UNATTENDED` **拒绝**
  （不是静默执行）；显式 `[[permissions]] allow` 仍然放行。
- `always_ask`：阈值更低，更多工具被拒；启动时 stderr 说明。
- `never_ask`：`askThreshold: null`，没有规则命中时全部放行——无人值守场景的
  **显式 opt-in**，只在沙箱照常时使用。

> **headless 的安全兜底是「权限规则 + OS 沙箱（Layer 2）」两层。** 需要
> 无人值守执行的工具请写 `[[permissions]] allow`（最小面），或明确接受风险后
> 设 `[approval] mode = "never_ask"`。默认 `ask_when_needed` 下被拒是设计
> 行为；启动时 stderr 会有一行提示，避免「模型说它要跑命令，然后什么也没
> 发生」。

因此启动期设了一道闸门（`validateHeadlessSafety`）：

- 沙箱照常（`enabled = true` 且 `preset = "workspace_write"`）→ 正常启动；
- `enabled = false` 或 `preset = "danger_full_access"`（两者最终都让命令
  回本地直执）→ **拒绝启动**，退出码 2：无人值守 + 无审批 + 无沙箱 =
  模型可无人监督执行任意命令，交互模式能接受的配置在这里不能；
- 确知风险要在无沙箱环境跑 headless（如已受控的容器），显式传
  `--allow-unsafe-headless` 放行——把「危险」变成调用方当场做出的决定，
  而不是配置文件里一处早已遗忘的设置。

同理，未声明风险的 MCP 工具缺省提级 `high`（见 conatus_mcp 的
`mcpToolRisk`）：stdio 子进程不经本地沙箱，审批是未知风险的唯一防线，
缺省必须进得去审批阈值。

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

在 [conatus](https://github.com/Fi2zz/conatus) 仓库内开发时，本仓库作为
submodule 挂在 `packages/conatus_code`。该仓库的 `tool/setup_code_filter.sh`
会：

- 装一个 git clean/smudge filter，让 `pubspec.yaml` 里的 `resolution:
  workspace` 在工作区保持生效 —— 本包成为 conatus pub workspace 的
  成员，依赖解析到本地 `packages/*`，改框架对这里立即生效，不必先推送；
  而 `git add` 时该行会被自动注释掉，推送出去的内容因此不带
  `resolution`；
- 生成一个本地 `pubspec_overrides.yaml`（已进 `.gitignore`），清空
  `pubspec.yaml` 的 `dependency_overrides` —— workspace 内禁止 override
  成员包。

未装 filter 的 clone（例如直接 clone 本仓库）拿到的是注释态、且 override
原样生效，行为与上面「独立使用」一致。

## 依赖

- [conatus](https://github.com/Fi2zz/conatus) — 框架
- Dart 3.6+；在 conatus 仓库内开发时需 3.11+（workspace 的 glob 语法要求）

## 与 conatus 的关系

conatus_code 是 conatus 的**上层应用**，不是框架的一部分。框架提供 Agent
Loop、工具系统、技能沉淀等底座；coding 相关能力（终端 UI、文件工具、代码
执行）原为 `conatus_tui` / `conatus_fs_tools` / `conatus_coding` 三个独立包，
**现已并入本包**，入口分别为 `lib/tui.dart` / `lib/fs_tools.dart` /
`lib/coding.dart`。本包负责装配这些能力并暴露终端界面。

## CI

`.github/workflows/test.yml` 在每次 push / PR 跑：静态检查（`--fatal-infos`）
→ 全部测试 → 打包二进制。跑在 `macos-latest`——沙箱 Layer 2 只在 macOS 可用，
`test/sandbox/` 下两个测试文件没有跳过保护，放到 ubuntu 上要么必红、要么被迫
跳过最有价值的那批。

CI 验的是**独立形态**：checkout 拿到的是提交态 pubspec（`resolution:
workspace` 被 git filter 注释掉，依赖经 git 拉 conatus master），也就是
「用户 clone 本仓库后拿到的东西」。conatus 工作区内的跨仓集成由 conatus
仓库的 CI 负责。

本仓库的 lint 规则因此**自包含**在 `analysis_options.yaml`（不像兄弟包那样
`include ../../analysis_options.yaml`）——独立形态下那个路径不存在。规则与
conatus 仓库根保持一致，改一处请同步另一处。

## 许可证

MIT
