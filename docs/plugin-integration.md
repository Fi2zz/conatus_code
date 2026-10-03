# 插件接入指南

nava 是 AOT 编译的 Dart 二进制，**运行时不加载插件代码**。接入任何插件的
原则有两条：

> 1. **插件方不需要写一行 Dart**。nava 侧把插件映射到已有机制——技能、MCP、
>    hooks、斜杠命令——按插件的接口形态分档接入。
> 2. **兼容现有插件体系，不发明新体系**。目标是让别的宿主（Claude Code、
>    Codex、Cursor 等）的插件尽量原样可用，nava 只做消费端适配，不定义
>    nava 专属的插件格式。

第二条原则直接排除了一批"看着诱人"的做法：

- ❌ 自定义插件 manifest（`plugin.toml` 之类）
- ❌ 自有插件目录约定与命名空间（`/plugin:*` 命令前缀）
- ❌ 插件市场 / 签名体系

生态里已有的原语——SKILL.md 技能约定、MCP 协议、`mcpServers` 配置形状、
Claude Code 插件仓库的目录形态——够用，缺的只是挂接点。本指南给出决策树、
每档的实操步骤、一个完整实例（superpowers），以及必须知道的信任边界。

## 决策树

```
这个插件是什么形态？
├─ 纯 Markdown 技能包（SKILL.md 目录）      → 形态一：挂载到技能发现根
├─ MCP server（JS / Python / 任何语言）     → 形态二：[mcp.servers.*] 配置
├─ CLI 或可执行脚本                          → 形态三：run_command 或 hooks
└─ 纯库（只暴露编程 API，无进程接口）         → 形态四：写一个 MCP 适配壳
```

四种形态覆盖当前 agent 生态插件的绝大部分，且全部落在 nava 现有机制上。

## 形态一：纯 Markdown 技能包

机制：技能系统从**发现根**（SkillRoot）扫描 `SKILL.md`，把目录（名称 +
一行描述）注入 system prompt，模型经 `skill` 工具按需取回正文——「模型可见
即已记录」，无需额外机制。

发现根（rank 小者赢下同名技能）：

| 层级 | 路径 | rank |
|---|---|---|
| 项目 | `<项目根>/.conatus/skills/` | 100 |
| 项目 | `<项目根>/.agents/skills/` | 200 |
| 用户 | `$CONATUS_HOME/skills/`（缺省 `~/.conatus/skills/`） | 400 |
| 用户 | `$CONATUS_AGENTS_HOME/skills/`（缺省 `~/.agents/skills/`） | 500 |

项目根 = 最近的含 `.git` 的祖先目录。frontmatter 支持
`name` / `description` / `whenToUse` / `disable-model-invocation`，
与主流技能格式兼容。

**`.agents/skills` 是跨宿主约定**：Claude Code、Codex 等都认这个目录，
项目级技能放这里对所有宿主同时生效。Claude 侧独有的 `.claude/skills/`
不在默认发现根，软链即可接入（是否要把它加进默认根，见文末兼容性矩阵）。

### 兼容细节：commands/*.md 直接可读

Claude Code 插件的 `commands/*.md`（frontmatter + 正文）与 SKILL.md 同构。
技能文件系统的 provider 同时接受两种形态：`<dir>/SKILL.md` 和发现根下
散落的 `<name>.md` 文件。所以把插件的 `commands/` 目录软链进发现根，
每条命令就变成一条可调用技能，不需要任何转换。

### 实例：接入 superpowers

[superpowers](https://github.com/obra/superpowers) 是 Claude Code 生态里
流行的开发工作流插件——纯 Markdown，由 `skills/` + `commands/` + `agents/`
+ 一个 session-start 脚本组成，无平台代码。它移植到 Codex 的方式是把
`skills/` 软链进 `~/.agents/skills`，对 nava 同样适用：

```bash
git clone https://github.com/obra/superpowers ~/.config/superpowers
ln -s ~/.config/superpowers/skills ~/.agents/skills/superpowers
```

启动 nava 后：

- 全部技能进目录、出现在 system prompt 技能目录段，模型可经 `skill` 工具
  调用；`disable-model-invocation` 的技能对用户手动触发可见
  （`/skill:<名字>`）
- 更新 = `cd ~/.config/superpowers && git pull`；发现根有文件监听，热生效

### 已知缺口：bootstrap 强制注入

superpowers 依赖 Claude Code 的 SessionStart hook 在会话开始时**强制**注入
`using-superpowers` 元技能（「先检索技能」是协议而非建议）。nava 的 hooks
目前只有 `pre_tool_use` / `post_tool_use` / `stop`，没有会话启动事件。

**绕行（现状可用）**：技能目录已在 system prompt 里，多数情况下模型会自行
发现并调用 `using-superpowers`；只是这是自觉行为，superpowers 作者明确
反对依赖自觉。

**补缺（未来小改动）**：给 hooks 加对称的 `session_start` 事件，stdout 落成
system prompt 常驻段（而非一次性消息，压缩后仍在）；或加配置式
`[bootstrap] skills = ["using-superpowers"]`，装配期把技能正文渲染成常驻段。
两者都是对称小特性，不需要动技能机制本身，也不引入新格式——SessionStart
是 Claude Code hooks 的既有事件名，照抄即兼容。

### 兼容性注意

- 技能正文引用的工具名是 Claude Code 的（`Task` / `Bash` / `Read` 等），
  nava 对应 `spawn_agent` / `run_command` / `read_file` 等，名字足够接近，
  模型一般能自行对上；严格要求可在项目 `.conatus/skills/` 放一份映射说明
  技能兜底
- 涉及写操作的技能（TDD、git worktree）触到的工具照常走审批与沙箱，
  不需要特殊处理

## 形态二：MCP server

agent 生态里大多数 JS/TS 插件本来就是 MCP server（数据库、浏览器、GitHub、
各类 SaaS 集成）。nava 的 stdio 传输就是为此准备的——**纯配置，零改动**：

```toml
[mcp.servers.github]
type = "stdio"
command = "npx"
args = ["-y", "@modelcontextprotocol/server-github"]
env = { GITHUB_TOKEN = "${GITHUB_TOKEN}" }   # ${KEY} 经凭据服务解析
```

- 工具自动以 `github__<tool>` 前缀进工具表（`/tools` 可见），按风险映射走
  当前权限模式的审批管线
- 单台连接失败提示并跳过，不阻塞启动；服务端断连自动注销其工具，其余
  server 照常（`/mcp` 看状态）
- `type = "http"` / `"sse"` 用 `url` + `headers`，同样支持 `${KEY}` 占位符
- **解析出的凭据不进日志、不进会话事件**

### 与生态标准配置形状的关系

生态里 MCP 的标准配置形状是 `mcpServers` JSON（Claude Desktop 的
`claude_desktop_config.json`、项目级的 `.mcp.json`）。nava 目前只认
config.toml 的 `[mcp.servers.*]`——形状等价但格式不同。支持直接读取项目级
`.mcp.json` 是个小改动（解析后映射进现有 `McpServerSpec` 装配，不新增
机制），属于兼容性矩阵里的待办项。

### 注意事项

1. **别裸用 `npx -y` 上生产**：每次冷启动要解析包且版本飘。常用 server 在
   固定目录 `npm i` 并提交 lockfile，config 写死路径与版本；`npx -y` 留给
   临时尝鲜。
2. **版本即信任级别**：`npx -y` 拉远端最新代码 vs 本地锁版本，风险完全不同。
   前者只在你审过包的情况下用。
3. stdio server 的子进程**不走 Layer 2 OS 沙箱**（MCP server 是用户显式声明
   的受信端，见 README「安全边界」）。接入第三方 server 等同于安装一个
   本地程序，按这个信任级别对待。

## 形态三：CLI 或可执行脚本

插件是一个能跑命令的程序（lint 器、生成器、检查脚本）：

- **偶尔调用**：让模型走 `run_command` 直接调，照常过 CommandPolicy 裁决与
  沙箱——无需任何配置
- **每次工具调用前后固定跑**：配成 hook。hook 经 `/bin/sh -c` 直连运行，
  写 JS/Python/任何脚本语言都可以：

```toml
[hooks]
pre_tool_use = ["node ~/.nava/hooks/check-env.cjs"]
post_tool_use = []
stop = []
```

hook 收到环境变量 `NAVA_HOOK_EVENT` / `NAVA_HOOK_TOOL` /
`NAVA_HOOK_ARGS_JSON`；pre 任一非零退出即拒绝该工具。

**注意**：hook 是**直连 shell、不经沙箱**的本机命令——它的权限等于运行 nava
的用户本人。只挂你信任的脚本。

Claude Code 的 `settings.json` hooks 是带 matcher 的结构化 JSON，与 nava 的
命令列表形状不同——不做自动映射，手工改写即可（事件名对照：
`PreToolUse`→`pre_tool_use`、`PostToolUse`→`post_tool_use`、`Stop`→`stop`，
其余 matcher 语义 nava 暂无对应）。

## 形态四：纯库（只暴露编程 API）

某 npm 包只提供编程接口、没有 CLI。这时**由你写几十行的 MCP 适配壳**，
插件作者完全无感。用官方 SDK 一个文件就够：

```js
// ~/.nava/wrappers/thing/server.mjs
// 依赖：npm i @modelcontextprotocol/sdk some-js-library
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/internals/stdio.js";
import { doThing } from "some-js-library";

const server = new McpServer({ name: "thing", version: "0.1.0" });

server.tool(
  "do_thing",
  "对输入执行 thing 并返回结果",
  { input: z.string() },
  async ({ input }) => ({
    content: [{ type: "text", text: String(await doThing(input)) }],
  }),
);

await server.connect(new StdioServerTransport());
```

config 里指向这个壳：

```toml
[mcp.servers.thing]
type = "stdio"
command = "node"
args = ["/home/you/.nava/wrappers/thing/server.mjs"]
```

适配壳是一次性成本，在你这边；对 nava 来说它只是一个普通的 MCP server。

## 信任边界速查

| 机制 | 信任级别 | 沙箱 |
|---|---|---|
| 技能（SKILL.md） | 指令文本，进模型上下文 = prompt 注入面 | n/a（只读文件） |
| MCP stdio server | 等同安装本地程序 | **不走 Layer 2** |
| MCP http/sse server | 远端端点，凭据经 headers | n/a |
| hooks | 等同你本人跑 shell | **直连，不经沙箱** |
| 形态三 `run_command` | 模型发起的命令 | 走 Layer 2 + 审批 |

原则：凡是你写进配置的受信端（MCP / hooks），nava 按你的显式声明放行；
凡是模型运行时发起的动作，走沙箱与审批。两类风险面不混。

## 排查清单

- `/mcp`：各 server 就绪状态与工具数；连接失败时启动期 stderr 有提示
- `/tools`：当前工具表全貌，确认 `server__tool` 前缀工具已注册
- `/doctor`：配置 / 沙箱 / 工具表 / MCP 逐项体检
- 技能没生效：确认发现根路径与 frontmatter（`name` / `description` 必填），
  项目根按最近的 `.git` 祖先判定
- MCP server 行为异常：先用独立 MCP 客户端（如官方 inspector）单独验 server
  本身，排除 nava 侧因素

## 兼容性矩阵

对齐现状一览（✅ 已兼容 / ○ 部分兼容 / ⚠️ 有缺口）：

| 现有体系 | 约定 | nava 现状 | 差距 |
|---|---|---|---|
| Skills | SKILL.md + frontmatter，`.agents/skills` | 发现根含项目/用户级 `.agents/skills`，frontmatter 兼容 | ✅ 基本零差距；`.claude/skills` 软链可入 |
| Claude Code 插件 | 仓库含 `skills/` `commands/` `agents/` `hooks/` | `skills/`、`commands/` 软链可入（`commands/*.md` 按散落 `.md` 技能直接读）；`agents/`、`hooks/` 无对应 | ○ 主体可用；SessionStart hook 是缺口 |
| MCP | `mcpServers` JSON（`.mcp.json` / `claude_desktop_config.json`） | 自有 TOML `[mcp.servers.*]`，形状等价 | ⚠️ 待支持读取 `.mcp.json`（小改动） |
| Hooks | Claude `settings.json` 结构化 hooks（matcher 等） | `[hooks]` 命令列表，事件名对照兼容 | ○ 手工改写，不做自动映射 |
| superpowers | 技能目录软链 + SessionStart 注入 | 技能软链 ✅ | ⚠️ bootstrap 强制注入缺口（见形态一） |

**明确不做的事**：自定义 manifest、自有插件命名空间、插件市场。当且仅当
某个生态标准本身要求一个新挂点时，才在消费端加适配（如 `.mcp.json` 解析），
且适配的产出必须落回现有机制（`McpServerSpec`、技能注册表），不得绕开。
