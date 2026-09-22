# conatus_code

> A terminal coding agent built on the conatus runtime.

## 是什么

基于 [conatus](https://github.com/Fi2zz/conatus) 构建的终端编码智能体。
复用 conatus 的 Agent Loop、工具系统、意图路由、技能沉淀，
专注 coding 场景。

## 特性

- 🖥️ 终端交互（基于 conatus_tui）
- 🔍 文件读写与搜索（read_file / write_file / edit_file / rg / glob）
- ⚡ 意图路由（高频命令零模型调用）
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

产出 `dist/conatio`（自包含：内嵌 Dart runtime，目标机器不需要装 Dart SDK）。
装到 PATH 的两种方式：

```bash
# 1. 软链到 PATH 上的目录
ln -s "$PWD/dist/conatio" /usr/local/bin/conatio

# 2. 或把 dist/ 加进 PATH
export PATH="$PWD/dist:$PATH"
```

之后直接 `conatio` 启动，`conatio --help` 看用法。脚本默认写到
`<包根>/dist/conatio`；第一个参数可覆盖输出路径，例如把产物写到
`/tmp/conatio`。

注意：OS 沙箱后端（launcher）仍在运行时从 pub 缓存定位，换机器或清理 pub 缓存后
沙箱会 fail-closed（命令执行被禁用，文件 jail 保留），这与源码运行时的行为一致。

## 配置

首次运行会读取 `~/.conatus-code/config.toml`（`CONATUS_CODE_HOME` /
`--config` 可覆盖路径）。示例：

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
network_allowlist = ["git fetch", "git pull"]
command_timeout_ms = 120000
max_output_bytes = 64000

[budget]
max_turn_seconds = 600        # 单轮墙钟上限（秒）；0 = 不限
max_turn_tokens = 200000      # 单轮上下文 token 估算上限；0 = 不限
```

## 模型提供商（`/provider` / `/model`）

提供商在 `~/.conatus-code/config.toml` 的 `[providers.<名字>]` 表里定义
（实现 `lib/src/providers/`，公开入口 `lib/providers.dart`）；`[llm]
default_model = "provider/model"` 同时定当前提供商与默认模型。`/provider` /
`/model` 命令**只读展示**注册表——增删改直接编辑 config.toml。**没有缺省回退
链**：未显式注入 `llm` 时，运行时用注册表当前提供商构造实例；两者都拿不到时
抛 `StateError`。

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
  review，当前按拒绝处理），再由 `SandboxedShellExecutor` 经 launcher 二进制
  在 Seatbelt 沙箱内执行，最小环境变量、不继承父进程环境。

**fail-closed 只作用于 Layer 2 后端**：launcher / Rosetta / Seatbelt 不可用时，
命令执行被拒斥执行器禁用（不降级为本地 shell），应用照常启动、Layer 1 文件
jail 继续生效。Layer 1 与 Layer 2 可独立关闭。

已知边界：

- launcher 默认无执行位，启动预检会 `chmod +x`；arm64 需 Rosetta 2，缺失时
  命令执行禁用（stderr 会提示，可在 config.toml 设 `[sandbox] enabled = false`
  关闭 Layer 2，保留 Layer 1 文件 jail）。
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
