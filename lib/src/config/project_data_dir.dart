/// 项目数据目录解析（会话 / 记忆 / 技能 / 检查点的存放根）。
///
/// 缺省放**用户配置目录**下（`$NAVA_HOME/projects/<编码后的规范工作区路径>`），
/// 不在工作区里建 `.conatus`；显式配置 `[agent] project_dir` 时才保持旧语义
/// `<workdir>/<project_dir>`（相对工作区）。编码用 [Uri.encodeComponent]，
/// 单级目录、可逆、无碰撞。
///
/// **拒绝**把数据目录指到 `.opencode`（项目级或全局）：那是用户自己 OpenCode
/// 的安装目录，nava 只读。落在那里会同时违反只读约束与检查点排除面
/// （检查点写 `.opencode.bak` 之类的数据文件，恢复时又被只读闸门挡住）。
/// 配置非法时回落到缺省目录，由 [projectDirProtected] 的调用方给出提示。
library;

import 'dart:io';

import '../read_only_paths.dart';
import 'config_path.dart';

/// 解析项目数据目录；[projectDir] 为 `[agent] project_dir` 原值（未配置为 null）。
String resolveProjectDataDir({
  required String workdir,
  String? projectDir,
  Map<String, String>? env,
}) {
  final String? explicit = cleanConfigValue(projectDir);
  if (explicit != null && !projectDirProtected(workdir, explicit, env: env)) {
    final String joined = _absolute(explicit)
        ? explicit
        : '$workdir${Platform.pathSeparator}$explicit';
    return joined;
  }
  return defaultProjectDataDir(workdir: workdir, env: env);
}

/// 缺省项目数据目录（`$NAVA_HOME/projects/<编码后的规范工作区>`）。
String defaultProjectDataDir({
  required String workdir,
  Map<String, String>? env,
}) {
  final String canonical = _canonical(workdir);
  return '${resolveConfigDir(env: env)}'
      '${Platform.pathSeparator}projects'
      '${Platform.pathSeparator}${Uri.encodeComponent(canonical)}';
}

/// [projectDir] 解析后是否落在受保护的 `.opencode` 根下。
///
/// 同时按字面与真实路径比较（符号链接指向 `.opencode` 也算）。
bool projectDirProtected(
  String workdir,
  String projectDir, {
  Map<String, String>? env,
}) {
  final String target = normalizeReadOnlyPath(
    _absolute(projectDir)
        ? projectDir
        : '$workdir${Platform.pathSeparator}$projectDir',
  );
  final String real = realPathViaAncestor(target) ?? target;
  final String? home = env?['HOME'] ?? env?['USERPROFILE'];
  for (final String root in defaultReadOnlyRoots(workdir, home: home)) {
    final String realRoot = normalizeReadOnlyPath(
      realPathViaAncestor(root) ?? root,
    );
    for (final String candidate in <String>[target, real]) {
      if (underReadOnlyRoot(candidate, root) ||
          underReadOnlyRoot(candidate, realRoot)) {
        return true;
      }
    }
  }
  return false;
}

String _canonical(String workdir) {
  try {
    return Directory(workdir).resolveSymbolicLinksSync();
  } on FileSystemException {
    return Directory(workdir).absolute.path;
  }
}

bool _absolute(String path) =>
    path.startsWith('/') || RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path);
