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
- 🔒 审批与沙箱（高危操作走审批；可选的 Seatbelt 进程沙箱 + 文件 jail）
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

## 配置

首次运行会读取 `~/.conatus-code/config.toml`（`CONATUS_CODE_HOME` /
`--config` 可覆盖路径）。示例：

```toml
[agent]
max_steps = 8                 # 单轮最大模型步数
workdir = "/path/to/project"  # 工作目录（沙箱根）；缺省当前目录

[approval]
mode = "ask_when_needed"      # always_ask / ask_when_needed / never_ask

[sandbox]
enabled = false               # 默认关闭；开启后走 jail fs + 沙箱命令执行
network_allowlist = ["git fetch", "git pull"]
command_timeout_ms = 120000
max_output_bytes = 64000
```

## 沙箱分层与已知边界

沙箱（`lib/src/sandbox/`，仅 macOS）由两层组成：

- **命令层**：`CommandPolicy` 裁决命令形状（管道 / 重定向放行；`&&`、`;`、
  `$()` 触发 review，当前按拒绝处理），再由 `SandboxedShellExecutor` 经
  launcher 二进制在 Seatbelt 沙箱内执行，最小环境变量、不继承父进程环境。
- **文件层**：`JailedFileSystem` 把 conatus `FileSystem` 接上
  `dart_io_sandbox` 的 bound jail，读写限定在沙箱根内，越界映射为
  `sandboxDenied`。

已知边界：

- launcher 默认无执行位，启动预检会 `chmod +x`；arm64 需 Rosetta 2，缺失时
  预检 fail-closed 报错退出。
- 审批判定 `REVIEW` 目前按拒绝处理（不启动进程），"REVIEW → 人工审批"
  未接线。
- 沙箱默认关闭（`[sandbox] enabled = false`），开启后进程隔离才生效。

## 预算护栏

每轮（空闲 2 分钟视为新一轮）默认 10 分钟墙钟 + 20 万估算 token 护栏；
超限时模型收到收口提示而非直接报错。估算按约 4 字符 1 token 的粗口径
（`estimateMessagesTokens`），**只作护栏，不用于计费**。成本跟踪
（`CostTrackerImpl`）按用量与粗略单价累计 `todayCost`，供未来的自主运行
预算检查消费。可用
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
