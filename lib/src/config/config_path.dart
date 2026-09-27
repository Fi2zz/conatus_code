/// 配置文件位置解析：`~/.nava/config.toml`。
///
/// 覆盖顺序（后者优先）：系统默认位置 → [kConfigHomeEnv] → `--config` 参数。
library;

import 'dart:io';

/// 用户级配置目录名，放在系统默认位置（macOS 为 `$HOME`）下。
const String kConfigDirName = '.nava';

/// 配置文件名。
const String kConfigFileName = 'config.toml';

/// 覆盖配置目录的环境变量名。
const String kConfigHomeEnv = 'NAVA_HOME';

/// 解析配置目录：`NAVA_HOME` 优先，否则 `$HOME`（Windows `USERPROFILE`）下的
/// 默认位置；用户目录无法定位时抛 [StateError]，绝不回退当前工作目录。
String resolveConfigDir({Map<String, String>? env}) {
  final Map<String, String> source = env ?? Platform.environment;
  final String? override = cleanConfigValue(source[kConfigHomeEnv]);
  if (override != null) return override;
  final String? home =
      cleanConfigValue(source['HOME']) ??
      cleanConfigValue(source['USERPROFILE']);
  if (home == null) {
    throw StateError('无法定位用户目录：请设置 HOME 或 $kConfigHomeEnv 环境变量');
  }
  return '$home${Platform.pathSeparator}$kConfigDirName';
}

/// 解析配置文件路径：`--config` 参数优先，否则配置目录下的 [kConfigFileName]。
String resolveConfigPath({String? explicit, Map<String, String>? env}) {
  final String? override = cleanConfigValue(explicit);
  if (override != null) return override;
  return '${resolveConfigDir(env: env)}${Platform.pathSeparator}$kConfigFileName';
}

/// 去掉首尾空白；空串归一为 `null`（TOML 里留空等价于未设置）。
String? cleanConfigValue(String? value) {
  final String? trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}
