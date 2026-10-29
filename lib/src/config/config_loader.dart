/// 读取 `config.toml`：定位 →（不存在则初始化）→ 解析 → 校验。
library;

import 'dart:io';

import 'package:toml/toml.dart';

import 'config_parser.dart';
import 'config_path.dart';
import 'config_schema.dart';
import 'config_values.dart';
import 'config_writer.dart';

export 'config_values.dart' show ConfigException;

/// 首次启动写入的配置模板（文件不存在时由 [loadConfig] 初始化）。
const String kDefaultConfigToml = '''
# nava 的唯一配置入口（~/.nava/config.toml）
# 兼容 kimi-code-config 格式：顶层 default_model（provider/model）定当前提供商
# 与默认模型；模型定义放 [models."provider/model"]；提供商放 [providers.<名字>]。

# default_model = "deepseek/deepseek-chat"

# OpenCode Go / Console（可选）：密钥在 https://opencode.ai/console 生成。
# Go 计划要求每个会话带 x-opencode-session，nava 绑定会话后自动发送
# （session_<uuid> → ses_<uuid>）；仅在 opencode.ai 主机上自动启用。
# 走代理或网关要求别的头名时，用 session_header 覆盖。
# [providers.opencode-go]
# api_key = "oc_sk_..."
# base_url = "https://opencode.ai/inference/go/openai/v1"
# type = "openai"
# session_header = "x-opencode-session"
# user_agent = "nava/0.1.0"
#
# Anthropic Messages（Go 的 Claude / MiniMax / Qwen 等模型）：
# [providers.opencode-go-anthropic]
# api_key = "oc_sk_..."
# base_url = "https://opencode.ai/inference/go/anthropic/v1"
# type = "anthropic"

# 韧性：单个提供商内先退避重试，仍失败再按 fallback_models 换下一个。
# [llm]
# fallback_models = ["deepseek/deepseek-chat", "ark/doubao-seed-2-0-lite-260215"]
# max_attempts = 4            # 总尝试次数（含首次）；1 = 关闭重试
# retry_base_ms = 500         # 首次退避，此后按 2 的幂翻倍
# retry_max_ms = 30000        # 单次退避上限（服务端 Retry-After 也受此约束）

# [models."deepseek/deepseek-chat"]
# capabilities = [ "always_thinking", "tool_use" ]
# max_context_size = 1000000

# 命名外部目录（只读）：相对 [agent] workdir / 绝对路径 / ~。
# [references.docs]
# path = "../product-docs"
# description = "产品文档，用于术语与行为说明"

# 额外技能目录（可选）：相对 [agent] workdir 或绝对路径 / ~。
# extra_skill_dirs = ["/path/to/skills"]
# true = 把 disable-model-invocation 的技能也放进模型可见目录（缺省 false）。
# merge_all_available_skills = false
# 装配期强制加载正文的技能（如 ["using-superpowers"]）。
# bootstrap_skills = []

# 非模型 Key（搜索等）仍走 [credentials]
[credentials]
# TAVILY_API_KEY = "tvly-..."
# BRAVE_API_KEY = "..."
# FIRECRAWL_API_KEY = "fc-..."

# 声明式自定义工具（可选）：CLI 或 HTTP 后端，参数 schema 显式声明。
# CLI：模型参数以 JSON 从 stdin 传入；stdout 支持 {"content": "..."} 或纯文本。
# 自定义工具是用户显式配置的受信端，默认 risk = "high"（进审批）。
# [[tools]]
# name = "deploy"
# description = "Deploy a service to an environment"
# command = "node"
# args = ["tools/deploy.mjs"]
# risk = "high"             # low / medium / high
# timeout_ms = 30000
# cwd = "tools"             # 相对 [agent] workdir
# env = { TOKEN = "\${TOKEN}" }
#
# [[tools.params]]
# name = "environment"
# type = "string"           # string / integer / number / boolean / enum
# required = true
# description = "target environment"
#
# [[tools.params]]
# name = "level"
# type = "enum"
# values = ["low", "high"]
# default = "low"
#
# HTTP 后端：url + method + headers（JSON body 与响应）。
# [[tools]]
# name = "lookup"
# description = "Look up a record"
# url = "https://tools.example.com/lookup"
# method = "POST"
# headers = { Authorization = "Bearer \${TOKEN}" }

# MCP server：工具经 server__tool 前缀接入；env / headers 支持 \${KEY} 占位符。
# 项目根 .mcp.json（Claude Code / OpenCode 的 mcpServers）也会自动读取，
# 同名 [mcp.servers.*] 优先；.mcp.json 是项目文件，stdio 子进程不经沙箱。
# [mcp.servers.filesystem]
# type = "stdio"           # stdio 用 command；http / sse 用 url
# command = "npx"
# args = ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
# [mcp.servers.remote]
# type = "http"
# url = "https://mcp.example.com/mcp"
# headers = { Authorization = "Bearer \${REMOTE_TOKEN}" }
# oauth = false             # 远程 server 缺省启用 OAuth；false 关闭
# [mcp.servers.remote.oauth]
# client_id = "..."         # 留空走动态注册（DCR）

# 检查点：每轮收口后对工作区文件做快照，/rewind 一键回滚。
[checkpoint]
enabled = true
keep = 5                    # 每会话保留最近 N 个检查点（0 = 不限）
# ignore = ["node_modules", "build/"]   # 额外忽略的相对路径前缀
# backend = "auto"          # auto(默认) 有 git 用影子仓库、无 git 用自研归档
                            # git / archive 为显式固定，不做自动降级
                            # 影子仓库更快：开第二个会话不必重拍全量

# XERJ 代码检索（可选）：需自行安装 https://xerj.org 的 xerj 二进制。
# 节点按需启动，数据目录不能放在被索引的工作区内。
# [xerj]
# enabled = true
# url = "http://127.0.0.1:19200"
# data_dir = "~/.nava/xerj"
# prefix = ""                 # 留空 = 按工作区派生独立索引前缀
# auto_index = true           # 编辑后后台增量刷新（项目至少索引过一次后生效）

# Hooks：工具执行前/后与轮次收口的用户命令（经 /bin/sh -c 直连运行）。
# [hooks]
# pre_tool_use = ["echo 将在工具前运行 > /tmp/nava-hook.log"]
# post_tool_use = []
# stop = []

# 人机双写故事层（可选，默认关闭）：开启后写工具先成待定补丁，
# /story 查看时间轴、apply/reject 待定补丁。关闭时行为与普通编码会话一致。
# [story]
# enabled = true

# lint-on-edit：模型编辑文件后自动跑 linter 并把告警塞回上下文。
[lint]
enabled = true
debounce_seconds = 10         # 去抖窗口（秒），防连续编辑连跑
# command = "dart analyze"    # 覆盖自动探测（默认按项目类型探测）

# TUI 外观（可选）：主题 default / dark / light / tokyonight（未知值回落 default）；
# animations 控制思考中动画等。也可在界面里用 /theme 切换（仅当前进程生效）。
# [tui]
# theme = "default"
# animations = true

# 全局键位（可选）：动作 ID 含点号，必须加引号；none / false 关闭该动作。
# <leader> 开头为两段式：先按 leader，2 秒内再按后续键。
# 动作：app.exit / app.clear / help.show / session.new / session.list /
#       model.list / agent.list / command.palette / theme.switch /
#       tab.next / tab.previous / tab.close
# 视图内按键（浮层 / diff / Ctrl+T / Ctrl+O）保持内置，不在此配置。
# [keybinds]
# leader = "ctrl+x"
# "app.exit" = "ctrl+c,ctrl+d"
# "app.clear" = "ctrl+l"
# "help.show" = "f1"
# "session.new" = "<leader>n"
# "theme.switch" = "<leader>t"
# "tab.next" = "none"          # 关闭某个动作

[agent]
# workdir = "/path/to/your/project"
# default_agent = "build"            # 新会话默认 Agent；未知 ID 回退 build
max_steps = 8
# subagent_permission = "inherit"   # 子代理默认权限：inherit/readonly/ask/auto
                                    # （模型可在 task 里收紧，不能放宽）

[approval]
mode = "ask_when_needed"   # always_ask / ask_when_needed / never_ask

# 权限规则（最外层工具中间件，先于审批 / hooks / lint / story 生效）：
# 按 action + resource 通配匹配，后出现的规则优先；任一条 deny 即拒绝。
# 动作：read / edit / glob / grep / shell / websearch / webfetch / subagent /
# skill / question / external_directory，也可直接写工具名。
# 路径动作的资源按工作区解析，符号链接按真实路径比较。
# [[permissions]]
# action = "bash"
# resource = "git push *"
# effect = "deny"
#
# [[permissions]]
# action = "edit"
# resource = "src/**"
# effect = "allow"

# 编辑后自动格式化（默认关闭；表存在即启用）。命令经 shell 缝执行，
# 沙箱拒绝时只提示、不失败工具。
# [formatter]
# command = "dart format"
# extensions = [".dart"]
# timeout_ms = 10000

# LSP（默认关闭）。启用后按扩展名启动配置的 stdio 语言服务器。
# [lsp]
# enabled = true
# [lsp.servers.dart]
# command = ["dart", "language-server"]
# extensions = [".dart"]

[budget]
max_turn_seconds = 600
# max_turn_tokens = 0        # 0 / 省略 = 按模型窗口的 75%；显式值只能更严
''';

/// 加载配置。
///
/// [path] 缺省按 [resolveConfigPath] 定位（`~/.nava/config.toml`）。
/// **文件不存在时先写入 [kDefaultConfigToml] 模板**（首次启动初始化），再照常
/// 解析；文件存在但语法或类型不合法时抛 [ConfigException]，**不静默降级**。
///
/// 注意：本函数读工作目录之外的路径，必须在沙箱 zone 之外调用（启动期即可）。
ConatusCodeConfig loadConfig({String? path, Map<String, String>? env}) {
  final String file = resolveConfigPath(explicit: path, env: env);
  final File source = File(file);
  if (!source.existsSync()) {
    // 走 writer 而不是直接写：它会 chmod 600。裸 writeAsStringSync 是 0644，
    // 模板里就含 API Key 的位置——本机 ~/.nava/config.toml 一直是这样。
    writeConfigFile(file, kDefaultConfigToml);
  }
  return ConfigParser(decodeToml(source), file).parse();
}

/// 读取并解析 TOML；语法或读取失败统一转成 [ConfigException]。
Map<String, dynamic> decodeToml(File source) {
  try {
    return TomlDocument.parse(source.readAsStringSync()).toMap();
  } on TomlException catch (error) {
    throw ConfigException('${source.path} 解析失败：$error');
  } on FileSystemException catch (error) {
    throw ConfigException('${source.path} 读取失败：${error.message}');
  }
}
