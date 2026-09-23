/// 读取 `config.toml`：定位 →（不存在则初始化）→ 解析 → 校验。
library;

import 'dart:io';

import 'package:toml/toml.dart';

import 'config_parser.dart';
import 'config_path.dart';
import 'config_schema.dart';
import 'config_values.dart';

export 'config_values.dart' show ConfigException;

/// 首次启动写入的配置模板（文件不存在时由 [loadConfig] 初始化）。
const String kDefaultConfigToml = '''
# nava 的唯一配置入口（~/.nava/config.toml）
# 兼容 kimi-code-config 格式：顶层 default_model（provider/model）定当前提供商
# 与默认模型；模型定义放 [models."provider/model"]；提供商放 [providers.<名字>]。

# default_model = "deepseek/deepseek-chat"

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

[agent]
# workdir = "/path/to/your/project"
max_steps = 8

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
    source.parent.createSync(recursive: true);
    source.writeAsStringSync(kDefaultConfigToml);
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
