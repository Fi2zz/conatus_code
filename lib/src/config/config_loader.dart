/// 读取 `config.toml`：定位 → 解析 → 校验。
library;

import 'dart:io';

import 'package:toml/toml.dart';

import 'config_parser.dart';
import 'config_path.dart';
import 'config_schema.dart';
import 'config_values.dart';

export 'config_values.dart' show ConfigException;

/// 加载配置。
///
/// [path] 缺省按 [resolveConfigPath] 定位（`~/.conatus-code/config.toml`）。
/// 文件不存在返回默认配置；文件存在但语法或类型不合法时抛 [ConfigException]，
/// **不静默降级**。
///
/// 注意：本函数读工作目录之外的路径，必须在沙箱 zone 之外调用（启动期即可）。
ConatusCodeConfig loadConfig({String? path, Map<String, String>? env}) {
  final String file = resolveConfigPath(explicit: path, env: env);
  final File source = File(file);
  if (!source.existsSync()) return const ConatusCodeConfig();
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
