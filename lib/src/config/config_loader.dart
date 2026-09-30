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

# 韧性：单个提供商内先退避重试，仍失败再按 fallback_models 换下一个。
# [llm]
# fallback_models = ["deepseek/deepseek-chat", "ark/doubao-seed-2-0-lite-260215"]
# max_attempts = 4            # 总尝试次数（含首次）；1 = 关闭重试
# retry_base_ms = 500         # 首次退避，此后按 2 的幂翻倍
# retry_max_ms = 30000        # 单次退避上限（服务端 Retry-After 也受此约束）

# [models."deepseek/deepseek-chat"]
# capabilities = [ "always_thinking", "tool_use" ]
# max_context_size = 1000000
# reasoning_key = "reasoning_content"
# support_efforts = [ "low", "high", "max" ]

# 非模型 Key（搜索等）仍走 [credentials]
[credentials]
# TAVILY_API_KEY = "tvly-..."
# BRAVE_API_KEY = "..."
# FIRECRAWL_API_KEY = "fc-..."

# MCP server：工具经 server__tool 前缀接入，高危按审批模式询问。
# env / headers 支持 \${KEY} 占位符（经凭据服务解析）。
# [mcp.servers.filesystem]
# type = "stdio"           # stdio 用 command；http / sse 用 url
# command = "npx"
# args = ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
# [mcp.servers.remote]
# type = "http"
# url = "https://mcp.example.com/mcp"
# headers = { Authorization = "Bearer \${REMOTE_TOKEN}" }

# 检查点：每轮收口后对工作区文件做快照，/rewind 一键回滚。
[checkpoint]
enabled = true
keep = 5                    # 每会话保留最近 N 个检查点（0 = 不限）
# ignore = ["node_modules", "build/"]   # 额外忽略的相对路径前缀
# backend = "auto"          # auto(默认) 有 git 用影子仓库、无 git 用自研归档
                            # git / archive 为显式固定，不做自动降级
                            # 影子仓库更快：开第二个会话不必重拍全量

# Hooks：工具执行前/后与轮次收口的用户命令（经 /bin/sh -c 直连运行）。
# [hooks]
# pre_tool_use = ["echo 将在工具前运行 > /tmp/nava-hook.log"]
# post_tool_use = []
# stop = []

# lint-on-edit：模型编辑文件后自动跑 linter 并把告警塞回上下文。
[lint]
enabled = true
debounce_seconds = 10         # 去抖窗口（秒），防连续编辑连跑
# command = "dart analyze"    # 覆盖自动探测（默认按项目类型探测）

[agent]
# workdir = "/path/to/your/project"
max_steps = 8
# subagent_permission = "inherit"   # 子代理默认权限：inherit/readonly/ask/auto
                                    # （模型可在 spawn_agent 里收紧，不能放宽）

[approval]
mode = "ask_when_needed"

[sandbox]
enabled = true
fs_jail = true
network_allowlist = ["git fetch", "git pull"]
command_timeout_ms = 120000
max_output_bytes = 64000

[budget]
max_turn_seconds = 600
max_turn_tokens = 200000
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
