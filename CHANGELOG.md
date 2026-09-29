# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

- 修一个**环境依赖的测试**：`tui_status_bar_test` 里 `resolveWorkspaceLocation`
  那条用例硬编码了分支名 `master`，且隐式用 `Directory.current`。换个 checkout
  形态就红——CI 用 `clone --recurse-submodules` 时子模块落在**游离 HEAD**
  （`rev-parse --abbrev-ref HEAD` 返回 `HEAD`），而生产代码正确地把 `HEAD` 当
  「无分支」处理。**测试错了，代码没错。**
  - `resolveWorkspaceLocation` 增可选 `cwd` 参数，让测试在**自建临时仓库**里断言
    有分支 / 游离 HEAD / 非 git 目录 / `~` 缩写四种情形，不再依赖调用者的 git
    状态。
  - 这条用例是新增的父仓库 `workspace-integration` CI job 暴露出来的——两个仓库
    的 CI 都绿，并不代表集成被验证过。

- **新增 `/export [路径]`**：把当前会话导出为 markdown（存档 / 分享 / 喂别的
  工具分析）。头带会话 id、时间、模型、工作目录、事件数、token、费率来源与成本。
  - 与 `/trace` 分工：`/trace` 回答「刚才那轮发生了什么」，只管屏上能读的一屏、
    会截断；`/export` 回答「把这次会话留下来」，**内容不截断**——截断是显示层的
    事。只有单条工具结果超 8000 字符才截，且**显式标注被截了多少**：静默截断会
    让读的人以为那就是全部。
  - 思考折叠进 `<details>`，内部事件（`agent/round` / `plan/updated`）不进导出；
    压缩留痕、压缩失败显式提示。
  - 缺省落项目数据目录的 `exports/`——**不在工作区留文件**，与会话 / 检查点同一
    取舍。给绝对路径或 `~` 路径则照写；以分隔符结尾视为目录并补上文件名。
  - 导出**不包含「导出」这条记录本身**（只写会话事件，不写屏上 system 消息）。
  - 落点不可写时把错误上屏并说明路径，不让异常逃到用户面前。

- **新增 `/trace [N]`**（缺省 1 轮）：把一轮的会话事件复盘成可读时间线——用户
  输入、模型思考、工具调用与结果、失败原因、压缩事件。回答「模型当时看到了什么、
  为什么那么判断」。
  - **不新建埋点**：会话日志本来就是可读 JSONL、事件也全都在盘上，缺的不是
    数据而是能看的入口。故直接渲染 `Session.events`，不引入第二套记录。
  - 失败项标 `✗` 并带出原因；不可读的事件（`agent/round` / `plan/updated`）
    跳过，不产生噪声行；压缩失败也显式提示。
  - 工具结果只取首行但**报出总行数**：`rg` 命中 12 处和 1 处是不同的信息，
    砍到首行不能把条数也丢了（初版只取首行，实跑 demo 时发现条数信息被吃掉）。
  - 与 `/doctor` 分工：`/doctor` 查装配（配置 / 沙箱 / 工具表），`/trace` 查
    这一轮发生了什么。

- **补齐 git 写操作工具**（`git_add` / `git_branch` / `git_stash`，均为
  `ToolRisk.medium`）。此前只有 `git_status` / `git_diff` / `git_commit` 三个，
  `/commit` 的提示词让模型「向用户说明并给出建议（如先 git add 暂存）」——
  nava 把例行步骤推回了用户：模型想自己暂存只能走 `run_command`，而它是
  `ToolRisk.high`，默认 `askWhenNeeded` 模式正好卡在 high 阈值上，于是每次提交
  都要弹一次审批框。
  - 三个工具**都不提供丢数据的入口**（无 `reset --hard` / `clean` /
    `switch -C` / `push --force`）——切分支丢工作区、误删未跟踪文件是开发里最贵
    的误操作，不该由模型来点。
  - `git_add` 缺 `all` 与 `paths` 时报错而非默认全量暂存：默认全量的话模型
    一次手滑就把整个仓库扫进去了。
  - `git_branch` / `git_stash` 支持 `list` / `restore` 只读档。
  - `_gitQuote` 公开为 `gitQuote`：写操作工具要拼 git 参数，两边各写一份转义
    迟早不一致。
- `/commit` 提示词改为完整流程（`git_status` → `git_add` → `git_diff --staged`
  → `git_commit`），不再让模型把暂存这步推给用户。

- **团队视图改成实时泳道**（`/team`）。此前是花名册：成员名 + 状态 + 任务描述，
  看不出成员在干什么还是卡住了；一次 `wait_agent` 可能 5 秒也可能 5 分钟，界面
  全程没有反馈。现在每个成员一条泳道，实时显示它调了什么工具、工具返回了什么、
  已经说了什么。
  - 框架侧（conatus_team）：新增 `TeammateActivity` 与 `TeammateActed` 事件。
    成员的 `MemberRuntime` 接管 `onStream`（正文 / 思考）并订阅自己的会话事件
    （工具调用在 `assistant` 事件里、结果在 `tool/result` 事件里，两条来源都要
    接才拼得出完整轨迹）。走 `changes` 同一入口而非另开流——界面已订阅 changes，
    多一条流就多一处可能漏订阅的地方。
  - 活动是高频事件（正文逐字来），故 `TeamSubscription` 拆成两条路径：活动只
    更新泳道（`MemberLaneBuilder` 就地维护，成员表 / 任务板原样带上），成员或
    任务变更才整份重建。
  - 每条泳道保留最近 12 行，连续正文合并成一行（`push` 里按标记前缀区分正文行
    与工具行）——否则一条长回答就能刷掉整个泳道。
- **子 Agent 也进泳道视图**（`SwarmProjection`）。`spawn_agent` 与 `AgentTeam`
  是两套并行的多 agent 机制（前者一次性委托、后者常驻成员），此前视图各有一套，
  「谁在干什么」被拆成两处。现把子 Agent 活动投影成同形的泳道（id 带 `swarm-`
  前缀，标 `◆`），复用同一套渲染与裁剪。
  - **只统一视图层，不动执行层**。让 `spawn_agent` 真正复用 team 机制要动
    conatus_agent 与 conatus_team 的包边界（团队的成员是常驻的、要挂任务板；
    委托是一次性的、拿回结论即销毁），语义不等价，属于另一次讨论。
- 修 `Ctrl+T` 键位冲突：`TeamView` 的提示语一直写着「按 Ctrl+T 返回对话」，但
  `Ctrl+T` 实际是展开 TODO 列表——同一个键两种行为，提示语在骗人。现在团队
  视图下 `Ctrl+T` 切视图，对话视图下才是展开 TODO。
- 接上 `TeamStatusBar` 的 `showCost`：此前这个参数**从来没被打开过**（全仓只有
  定义处，默认 false），状态栏的成本位一直是 0。成本取共用的 costTracker
  真实费率（`conatus_code` 侧 `_CostBridge`），不另开一套计费。

- **子 Agent 进度实时上屏**（`spawn_agent`）。此前子 Agent 跑在自己的
  `Session` 上、那个会话不参与屏上记录，于是它是黑箱：界面静止几十秒，结束后
  只吐一段结论字符串，看不出它调了什么、卡在哪、是不是跑偏。现在经
  `SubAgentProgressStore` 逐条广播起手 / 每轮 / 工具调用与返回 / 收口，控制器
  订阅后写成 `TuiRole.stage` 暗色行。看不见就不敢用——这是让它值得用的前提。
- **子 Agent 预算独立于主轮次**。此前 `provideSpawnAgent` 取 app 上的 `'llm'`，
  那已经是 `BudgetedLlmProvider`；子 Agent 跑的每一轮都记进**主**轮次的 token
  计数器，`[budget] max_turn_tokens` 会在它跑到一半时把整个主轮次收口，而它
  的半截结论会被当成结论回传。现传未包装的 `resolvedLlm`，并用 `childLlm`
  工厂为每次委托新建一个自己计数的包装。成本仍记进同一个 costTracker。
- 已知未做：子 `AgentLoop` 仍不接 compactor / memory，调研型子任务历史长了
  不会被压缩；默认白名单仍只有 `get_time` / `echo` / `read_file`，也没有
  中途 interrupt。这些留待实际用起来之后再按需补。

- **修 `/cost` 恒为 $0**：`BudgetedLlmProvider.chatStream` 此前直接 `yield*`
  透传、从不调 `recordUsage`，而 TUI 始终带 `onStream` 走流式——用量永远记不上，
  成本追踪在真实路径下完全失效。改为在透传时盯住终态帧
  （`LlmStreamDone.usage`，用量只出现在流末尾）。
- **修 Responses 形态成本恒为 0**：`CostTrackerImpl` 只读 Chat Completions 的
  `prompt_tokens` / `completion_tokens`，而 `type = "kimi"`（Ark / responses）
  返回 `input_tokens` / `output_tokens`。两种键名现在都收，并支持
  `prompt_tokens_details` / `input_tokens_details` 里的缓存命中数按折价计。
- **成本改用真实费率**（models.dev），删掉写死的 `kInputRatePerMillion = 0.3` /
  `kOutputRatePerMillion = 1.2`——那两个常数对 DeepSeek 差一个量级、对 Gemini
  差得更多，且用户无从判断那个数字是编的。费率查不到时 `/cost` 明说「未知」
  并按 0 计，而不是报一个假数字。
- **上下文窗口真正参与决策**，不再只画在状态栏上：
  - 单轮 token 封顶改为 `min(模型窗口 × 0.75, [budget] max_turn_tokens)`。
    此前是写死的 20 万——32k 窗口的模型永远等不到这条闸门（请求先被 API 拒
    掉），1M 窗口的模型又在 20% 处过早收口。模型窗口是硬约束，配置只能让封顶
    更严，不能放宽到超过窗口。
  - 状态栏分子在有真实用量后改用接口返回的 `prompt_tokens`（含 system
    prompt、工具定义、工具结果），比按屏上记录 chars/4 猜准得多；首轮之前的
    估算值前缀加 `~`。
- 新增 `ModelProfileStore`（挂 `'modelProfiles'` 服务）：装配期后台预热
  models.dev，同步查档案，拿到后广播。顺带修掉每次 `start()` 都走一次网络
  拉取整份 models.dev 的问题（冷启动可达 30s），现在复用 24h 磁盘缓存。
  provider 名对不上时按模型 id 跨 provider 查——窗口与价格是模型属性。
- `/cost` 改为分列输入/输出/缓存命中 token 与调用次数，并讲清费率来源。
- `/doctor` 新增「模型窗口 / 费率」项。
- 修 `subprocess_runtime_test` 的临时目录断言：此前数系统临时目录下 `nava-`
  前缀的**总数**，而并行跑的 28 个其它测试文件各自建 `nava-cp-*` / `nava-lint`
  等目录，全量跑时偶发「多了一个」，与被测代码无关。改为从命令串取出本次执行
  真正用到的那条路径再断言。

- 新增 CI（`.github/workflows/test.yml`）：push / PR 触发，跑 `dart analyze
  --fatal-infos` → 全量测试 → 打包二进制并 `--version` 自检。此前 709 个测试
  只在本机跑过，每次 push 都没有验证；打包路径更是从未被自动验证过。
  跑在 `macos-latest`（沙箱只在 macOS 可用），钉死 Dart 3.12.2，缓存 pub。
  刻意不加 Gitee 镜像——发布路径只有 `dist/nava` 二进制，不走仓库分发。
- 修 `analysis_options.yaml` 在独立形态下失效：它只有一行
  `include: ../../analysis_options.yaml`，而独立 clone（本仓库 README「快速开始」
  给出的安装方式）里那个路径不存在，include 失败导致整套 lint 规则不生效，
  `dart analyze` 报 `include_file_not_found`。改为自包含（规则与 conatus 仓库根
  一致）。兄弟包的同一写法保留——它们不作为独立仓库分发。

- 新增 **LLM 回退链**（`[llm] fallback_models`）：主模型失败后按序尝试备用
  `provider/model`，每项可同 provider 换模型（换模型比换网关更常见的降级手段）。
  此前只有单提供商——README 明写「没有缺省回退链」，一次 401 或一次持续限流就
  让整轮报废。
- 单个提供商内先**退避重试**（`[llm] max_attempts` / `retry_base_ms` /
  `retry_max_ms`，缺省 4 次 / 500ms 起翻倍 / 封顶 30s），限流 / 5xx / 网络故障
  照 `Retry-After` 或指数退避重试；401、缺 Key、4xx 不重试，直接进回退链。
  链路形状为 `FallbackLlm(RetryingLlm(主), RetryingLlm(备), …)`——先在原提供
  商上把能救的失败救回来，避免一次抖动就换模型、让回答风格在一次会话里来回跳。
- 重试与回退**实时上屏**（`· ark 触发限流，1.0s 后重试（2/4）`、`· ark 不可用，
  已切到 deepseek`）：退避可能静默 30 秒，没有提示在用户眼里就是卡死。提示经
  `LlmNotices` 出口广播（挂在 `'llmNotices'` 服务上），控制器订阅后写进屏上记录
  并随控制器销毁取消订阅。
- `/doctor` 新增「模型回退链」项：报出候选链、被跳过的无效配置项、以及最近一次
  回退。回退是静默发生的，没有这一项用户只会看到回答风格突然变了。
- 配错的回退项（provider 不存在 / 重复 / 形态非法）**跳过而不是整体失败**，并
  记进 `LlmChain.skipped`：`provider/model` 形态错误在解析期即报错并指出是哪
  一条，其余在装配期跳过。配错一条备用模型不该让主模型都用不了。
- 缺凭据的 provider 仍进链而非装配期拒绝：凭据可能随后经凭据服务轮换进来；
  真到调用时缺 Key 属于不可重试的 `config` 类错误，立即失败并回退到下一个。
- `/model` 切换主模型时**重建整条链**，配置里的 `fallback_models` 仍跟随——
  此前切换会把回退丢掉，等于让一条命令顺手关掉了容错。
- 首次启动生成的 config.toml 模板补上 `[llm]` 韧性字段的注释示例。

- 检查点存储新增「影子 git 仓库」后端，`[checkpoint] backend` 可选
  `auto`（缺省）/ `git` / `archive`。`auto` 在有 git 时用影子仓库、无 git
  时退回自研 gzip 归档（零外部依赖，任何环境可跑）；`git` / `archive` 是
  显式固定，不做自动降级——写死 `git` 而环境无 git 时每轮快照会报错，比
  悄悄换实现更容易察觉问题。
- 影子仓库的收益：内容寻址 + zlib + 增量全交给 git。同一工作区
  （2000 文件 / 125MB 合成数据）实测——开**第二个会话**的 turn 0 从 4.36s
  降到 239ms（归档实现每次开会话都要重付全量代价），这也是「新会话卡在
  正在加载会话…」的根因。代价是多文件小文件场景占用更高（39.9MiB vs
  24MiB，git 按 blob 各自 zlib，跨文件上下文不如单条 gzip 流）。
  新增 `tool/bench_shadow.dart` 可复测。
- 影子仓库**不要求工作区本身是 git 仓库**，也不碰用户仓库（实测：影子提交
  后用户 `git log` 不变、`status` 只多 untracked）。仓库位于项目数据目录下
  `checkpoints/shadow.git`，随会话数据一起备份。
- 快照排除面统一由 conatus 自己算（`checkpointWalk`），不再委托 git 的
  ignore 机制：影子实现曾用 `git add --all`，git 会顺从**工作区的
  `.gitignore`**，与归档实现的排除面不一致——恢复按 rsync 语义把「不在目标
  态」的文件删掉，实测在 9661 文件的 swiftus 上快照只收 293 个、恢复删掉
  其余 9119 个。现改为自行 walk 后把路径显式喂给 `git add -f`，并加
  `_verifyStaged` 断言：暂存不完整就中止本轮快照并报错，绝不静默产出残缺
  快照。嵌套 git 仓库（`git worktree` / vendor）整树排除——`git add` 对其
  内部路径会**静默跳过**（rc=0 无告警）。归档实现同样改用共用遍历，顺带
  修掉它删除侧的同一个洞。
- 快照默认排除敏感文件（凭据 / 私钥）：`.env` 及变体、`.pem`/`.key`/`.p12`
  等后缀、`id_rsa` 一类、`credentials.json`、`secrets.*`、`.netrc` 等；放过
  `.env.example`/`.sample`/`.template` 与 `.envrc`。理由：快照是明文落盘
  （gzip 不是加密），影子实现还会把内容写进 git 对象库，删掉检查点后 blob
  仍留在库里。排除是双向的——也不会在恢复时被当成「多余文件」删掉。
- 快照排除**全局** gitignore（`core.excludesFile`）忽略的路径：机器级
  housekeeping（`.DS_Store`、`*~` 等）进快照无价值。**不**排除工作区的
  `.gitignore`——「不进版本库」不等于「不该备份」，构建产物恰恰是最需要能
  被回滚的。用 `git check-ignore --verbose` 按「来源」筛选，无需自己解析
  gitignore 语法。该集合并入 `checkpointExcluded`，采集与删除判定同源。

- 默认目录全部收敛到用户目录、零 cwd 兜底：`resolveConfigDir` 无 `HOME` 时改用
  `USERPROFILE`，仍缺失抛 `StateError`（此前静默落当前工作目录）；
  `ConatusTuiRuntime.create` 的 `baseDir` 缺省由 `<cwd>/.conatus` 改为
  `resolveProjectDataDir`（与 CLI 入口一致）；TUI 的 database 随之集中到
  `<项目数据目录>/database`（此前散在 `<cwd>/.conatus/database`）。
- 项目数据目录移出工作区：缺省落 `~/.nava/projects/<编码后的规范工作区路径>`
  （新 `resolveProjectDataDir`，`NAVA_HOME` 优先），不再在每个项目里建
  `.conatus`；显式 `[agent] project_dir` 才保持相对工作区的旧语义。
  `AgentConfig.projectDir` 缺省由 `'.conatus'` 改为未设置（null）。旧工作区
  `.conatus` 里的历史会话不再自动发现（数据保留不删）。
- 修复工作区含二进制文件时每轮快照报「检查点保存失败：FormatException:
  Invalid UTF-8 byte」：`readCheckpointManifest` 曾把整个解压流过
  `utf8.decoder` + `LineSplitter` 取首行，清单头之后的条目内容是任意二进制
  （图片 / 编译产物 / 压缩包），解码器一越过行尾就抛 `FormatException`——
  尽管我们只想读第一行。现按字节找行尾、只解码切出的头部那一段（头是 JSON，
  必然合法 UTF-8）。差量快照每轮都要读基线清单，故此问题表现为「每轮都
  失败」。`readCheckpointEntries` 不受影响（只对路径解码，内容按原字节还原）。
- 修复大工作区「正在加载会话…」久等（界面被检查点基线挡住）：会话绑定不再
  `await` turn 0 基线快照——`ready` 先置位、历史立即可读，基线在后台起拍。
  首轮（`submit`）与 `/rewind` 前各有一道门闩等基线落定，避免快照飞行中被
  工具改动拍出「半旧半新」的 base。`CheckpointManager` 的 `reset` /
  `recordTurn` / `detach` 改走串行链，差量必晚于基线；`detach` 递增代数让
  在途基线自行放弃（换会话时不再写盘）。新增
  `ConatusTuiController.checkpointSettled` 供外部在「就绪但基线未落盘」的
  窗口显式同步。
- 基线快照的工作区内容由**读两遍降为读一遍**（894MB 工作区实测 21.3s →
  19.6s）：旧实现 pass 1 为算 sha256 整文件读入、pass 2 再整文件读一遍写
  归档。现清单头只留 `path`/`mtime`/`size`（`stat` 即可得，全量 55ms），
  内容哈希在 pass 2 流式写 gzip 的同一遍里顺带算出（`crypto` 分块接口，
  内存 O(chunk)），落 `<归档>.hashes` 旁挂文件；差量据此做「mtime+size 未变
  但内容变」的兜底判定。旁挂缺失/损坏时保守按变化处理（与旧语义一致）。
  新增 `tool/bench_snapshot.dart` 量基线耗时。
- 归档层曾把整包文件内容全量读进内存（base 快照 660MB 工作区 ≈ 2GB RSS、
  数十秒）。现归档读写全程流式——新增 `CheckpointArchiveWriter`（清单头先行、
  条目按 chunk 过 gzip）、`readCheckpointManifest`（只读头部、不再整包
  解压）、`readCheckpointEntries`（逐条产出）；base/差量快照两遍式流式落盘，
  `/rewind` 恢复按条目写盘，内存 ≈ 最大单文件。排除面内置 `.git` /
  `.conatus` / `build` / `.dart_tool` / `node_modules` 顶层前缀
  （`kCheckpointDefaultIgnores`），与 `[checkpoint] ignore` 取并集。

- 沙箱 REVIEW 接线人工复核：TUI 内经选项浮层征询（展示命令与复核理由，
  NeverAsk 视同放行），批准后命令在 seatbelt 内照常执行；人工拒绝/超时/
  回调故障均按拒绝（fail-closed）。headless 无浮层，REVIEW 维持拒绝。
  `CommandPolicy` 复核形状时仍查可执行白名单与越界路径——确定性违规
  优先 deny，人工复核只豁免命令形状顾虑。`SandboxedShellExecutor` 新增
  运行期可接线的 `reviewPrompter`（`SandboxReviewPrompter`）。
- `[background] keep_alive_on_exit` 生效：缺省 `false` 时 nava 退出即终止
  所有在跑后台任务（`BackgroundTaskService.shutdown` 随根上下文 dispose
  调用，TUI 与 headless 同路径）；置 `true` 退出不杀、任务保活脱离——
  脱离后不受 `/background` 管理，输出管道随进程退出关闭。

- 修复 `!` shell 模式误用模型命令策略：用户直发命令此前走 `'shell'` 沙箱缝，
  被可执行白名单（`which` 等日常命令不在列）与路径越界裁决（`cat ~/.zshrc`
  等）整批拒绝，"系统命令全部无法用"。现改走 `'shellInteractive'` 交互缝
  缺省本地直执（对齐 OpenCode），模型发起的 `run_command` 等仍完整过沙箱。
- `!` 命令未找到（exit 127）时错误行原样直出（如 `bash: fork: command not
  found`），不再包「命令失败（exit 127）」前缀，观感与终端直出一致。
- 状态栏左段恢复「权限模式 + 模型」组合展示（权限黄色 / 模型亮色，三空格分隔），
  修复 UI 微调时把 `Text(left)` 误改为只渲染权限标签、模型消失的问题；权限模式
  标签统一为英文（Always Ask / Ask When Needed / Never Ask），相关测试同步对齐。
- 修复沙箱集成测试守卫：`markTestSkipped` 在当前 test 版本下只标记不终止，
  无沙箱环境会以空断言报错而非跳过；标记后显式抛 `StateError` 终止。
- `config.toml` 创建与每次写入后 `chmod 600`（Windows 跳过），避免明文
  API Key 被同机其他用户读取。
- `!` 快捷 shell 模式：输入 `!<命令>` 直接执行不经模型（走沙箱缝）；`!!`
  重跑上一条；busy 时拒绝。
- shell 模式对齐 OpenCode：空提示符打 `!` 进入（输入框 `!` 前缀 + shell 占位 +
  状态栏 `[Enter] 执行 | [Esc] 退出`），Esc 不执行退出，执行完自动退出回对话模式。
- 修复 `!` 命令结果不上屏：`Transcript.add` 不触发重绘，执行后显式刷新，
  不再等下一次按键才看到输出（沙箱执行本身约 30ms）。
- shell 模式下输入框边框变紫色（普通模式仍为蓝色），一眼区分当前在跑 shell。
- `/review`：审查当前未提交改动（命名/边界/安全/性能，只审不改），与
  `/commit` 组成「写完 → 自查 → 提交」闭环。
- lint-on-edit：模型编辑文件（write_file/edit_file/apply_patch）后自动跑
  linter 并把告警塞回工具结果当场闭环；`[lint]` 配置（enabled/command 覆盖/
  debounce_seconds），按项目类型探测（dart analyze / eslint / go vet / cargo check）。
- checkpoint 存储改为**单文件压缩归档 + 不可读文件名**：每个检查点是一个无扩展名
  文件（文件名 = `sha256("<会话>:<轮次>")` 前 16 位哈希，**不可读、无 `.gz` 扩展
  名、不暴露轮次时间线**；轮次只记录在归档头与会话级 gzip `index` 里，`list`/
  `prune` 只读索引不逐个解包），整个检查点打包成一个文件、不保留目录结构、内容
  非明文（`dart:io` 内置 GZipCodec 自定义容器格式，零新依赖）；旧版目录树检查点
  读时兼容、索引缺失自动重建。
- checkpoint 存储改为**单文件压缩归档**：每个检查点是一个 `.gz` 文件（`<会话>/<turn>.gz`），
  整个检查点打包成一个文件、不保留目录结构、内容非明文（`dart:io` 内置 GZipCodec
  自定义容器格式，零新依赖）；旧版目录树检查点读时兼容。
- checkpoint 存储改 **gzip 压缩**：快照文件与清单均以 `.gz` 落盘（`dart:io`
  内置 GZipCodec，零新依赖），内容不以明文显示；读时自动回退旧明文文件
  （升级前检查点兼容）。
- `/commit`：提交流程命令——模型查看暂存 diff、写 Conventional Commits 提交
  信息并经新的 `git_commit` 工具提交（high 风险走审批）。
- `/doctor`：体检命令——配置 / 提供商 / 沙箱（Layer 1/2）/ 工具表 / MCP /
  rg 逐项 ✓/✗ + 修复提示。
- Hooks：config.toml `[hooks]` 表（pre_tool_use / post_tool_use / stop），
  事件命令经 `/bin/sh -c` 直连运行（不走沙箱缝）；Pre 非零退出拒绝工具、
  Post/Stop 失败只提示；注入 `NAVA_HOOK_EVENT/TOOL/ARGS_JSON` 环境变量。
- delta 哈希级变化检测：checkpoint base 条目记录 SHA-256，mtime+size 相同时
  读内容哈希比对（修「内容变但 stat 不变」漏检）；旧清单保守按变化处理。
- 后台任务执行器：`run_command_background` 在沙箱中后台启动命令（返回 `bg-<n>`），
  `list_background_tasks` / `background_output` / `background_kill` 管理；`/background`
  用户命令入口；并发上限读 `[background] max_running_tasks`（复用 `ShellExecutor.start`
  能力缝）。任务随进程退出而结束。
- 消息队列：busy 时输入自动排队（上限 20 条），收口后依次投递；`Esc` 打断与切会话
  清空队列；cron/提醒投递不受影响。
- checkpoint delta 快照：turn 0 全量 base + 各轮相对 base 的差量（只复制变化/新增，
  删除记入清单，mtime+size 变化检测）；恢复为 base 铺底 + 差量覆盖/删除；base 永不
  prune（回滚锚），保留 base + 最近 `keep-1` 个差量。旧格式清单兼容读。
- `/rewind` 对话回滚（checkpoint v2）：检查点清单记录对话切点事件 id，
  `/rewind [N]` 在恢复工作区文件的同时把对话回滚到该轮——从切点
  `Session.fork` 出新会话（旧会话保留为记录），切点为空（全新会话的
  turn 0）时切到全新空会话。框架层 `SessionStore.adopt` 支持注册外部
  fork 会话并整体落盘继承种子（重开不丢历史）。
- 检查点 / 回滚（`/rewind`）：每轮收口后对工作区文件做快照（含绑定时的 turn 0
  初始态），存 `<项目数据目录>/checkpoints/<会话>/<turn>/`（排除 `.conatus` /
  `.git` / `[checkpoint] ignore` 前缀，保留最近 `keep` 个）。`/rewind [N]` 把
  工作区恢复到 N 轮前（缺省 1）的文件状态，`/rewind list` 查看可用检查点；
  **只回滚文件、不改会话与对话**。新增 `[checkpoint]` 配置表
  （enabled / keep / ignore）。
- Headless 非交互模式：`nava -p "<任务>"` 单轮执行、跑完即退出，支持
  `--output-format text|json` 与 `--session` 恢复（CI/脚本可用）；headless 不装
  审批浮层与 `ask_user`（高危工具直执，沙箱兜底）；配置错误退出码为 2、轮次
  失败为 1。
- 项目上下文：启动加载工作目录根的 `AGENTS.md` / `NAVA.md` 注入 system prompt
  （单文件超 16 KB 截断）；新增 `/init` 让模型扫描仓库生成 / 更新 AGENTS.md。
- 小命令批：`/compact` 手动压缩（折叠 20 条之后的早期历史）、`/cost` 展示今日
  估算成本与 token 用量、`--version` 打印编译期注入的版本号、`--continue` 恢复
  最近一次会话（`--session` 优先）。
- MCP（Model Context Protocol）接入：config.toml `[mcp.servers.<名字>]` 表声明
  server（stdio / http / sse），启动时逐台挂载、单台连接失败提示并跳过；工具以
  `server__tool` 前缀进工具表，风险映射走既有审批链；`env` / `headers` 支持
  `${KEY}` 凭据占位符（解析结果不写日志）。新增 `/mcp` 命令查看已接入 server。
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
