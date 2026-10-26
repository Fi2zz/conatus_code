/// `nava import opencode` 的参数解析。
library;

/// 解析结果；参数不合法时 [error] 非空。
class ImportInvocation {
  const ImportInvocation({
    this.write = false,
    this.globalOnly = false,
    this.projectOnly = false,
    this.configPath,
    this.workdir,
    this.help = false,
    this.error,
  });

  final bool write;
  final bool globalOnly;
  final bool projectOnly;
  final String? configPath;
  final String? workdir;
  final bool help;
  final String? error;
}

/// 解析 `nava import` 之后的参数；顶层用法错误返回 `null`。
ImportInvocation? parseImportArgs(List<String> args) {
  if (args.isEmpty) return null;
  if (args.first == '--help' || args.first == '-h') {
    return const ImportInvocation(help: true);
  }
  if (args.first != 'opencode') return null;
  bool write = false;
  bool globalOnly = false;
  bool projectOnly = false;
  String? configPath;
  String? workdir;
  for (int index = 1; index < args.length; index++) {
    final String arg = args[index];
    if (arg == '--write') {
      write = true;
    } else if (arg == '--global-only') {
      globalOnly = true;
    } else if (arg == '--project-only') {
      projectOnly = true;
    } else if (arg == '--config' || arg == '--workdir') {
      if (index + 1 >= args.length) {
        return ImportInvocation(error: '$arg 缺少路径。');
      }
      final String value = args[++index];
      if (arg == '--config') {
        configPath = value;
      } else {
        workdir = value;
      }
    } else if (arg == '--help' || arg == '-h') {
      return const ImportInvocation(help: true);
    } else {
      return ImportInvocation(error: '未知参数：$arg。');
    }
  }
  if (globalOnly && projectOnly) {
    return const ImportInvocation(
      error: '--global-only 与 --project-only 不能同时使用。',
    );
  }
  return ImportInvocation(
    write: write,
    globalOnly: globalOnly,
    projectOnly: projectOnly,
    configPath: configPath,
    workdir: workdir,
  );
}
