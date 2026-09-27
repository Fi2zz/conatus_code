/// 项目数据目录解析（会话 / 记忆 / 技能 / 检查点的存放根）。
///
/// 缺省放**用户配置目录**下（`$NAVA_HOME/projects/<编码后的规范工作区路径>`），
/// 不在工作区里建 `.conatus`；显式配置 `[agent] project_dir` 时才保持旧语义
/// `<workdir>/<project_dir>`（相对工作区）。编码用 [Uri.encodeComponent]，
/// 单级目录、可逆、无碰撞。
library;

import 'dart:io';

import 'config_path.dart';

/// 解析项目数据目录；[projectDir] 为 `[agent] project_dir` 原值（未配置为 null）。
String resolveProjectDataDir({
  required String workdir,
  String? projectDir,
  Map<String, String>? env,
}) {
  final String? explicit = cleanConfigValue(projectDir);
  if (explicit != null) {
    return '$workdir${Platform.pathSeparator}$explicit';
  }
  final String canonical = Directory(workdir).resolveSymbolicLinksSync();
  return '${resolveConfigDir(env: env)}'
      '${Platform.pathSeparator}projects'
      '${Platform.pathSeparator}${Uri.encodeComponent(canonical)}';
}
