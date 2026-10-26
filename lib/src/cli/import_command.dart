/// `nava import opencode`：把 OpenCode 配置映射进 nava config.toml。
///
/// 默认 dry-run，只打印将新增的片段；`--write` 才原子落盘。项目配置不会在
/// 启动时自动生效——这是显式导入，不是运行时合并。
library;

import 'dart:io';

import '../config/config_path.dart';
import '../config/config_writer.dart';
import 'opencode_import_map.dart';
import 'opencode_import_plan.dart';
import 'opencode_import_source.dart';
import 'opencode_import_types.dart';

/// `nava import opencode` 的用法。
const String kImportUsage = '''
用法：nava import opencode [选项]
  --write                 真的写入 config.toml（缺省只打印片段）
  --global-only           只读 ~/.config/opencode
  --project-only          只读项目/祖先目录的 opencode.json(c)
  --config <路径>         目标 nava 配置（缺省 ~/.nava/config.toml）
  --workdir <路径>        项目发现起点（缺省当前目录）
  --help                  显示本帮助

支持：model / default_agent / mcp.servers / permissions / instructions。
agents / commands / providers / plugins / lsp / references / policies /
formatter / tools / skills 暂不支持，会列出告警。''';

/// 解析并执行导入，返回进程退出码。
Future<int> runImportCli(
  List<String> args, {
  StringSink? out,
  StringSink? err,
  Map<String, String>? env,
  String? homeDir,
}) async {
  final StringSink stdoutSink = out ?? stdout;
  final StringSink stderrSink = err ?? stderr;
  final _ImportInvocation? invocation = _parse(args);
  if (invocation == null) {
    stderrSink.writeln(kImportUsage);
    return 2;
  }
  if (invocation.help) {
    stdoutSink.writeln(kImportUsage);
    return 0;
  }
  if (invocation.error != null) {
    stderrSink.writeln(invocation.error);
    stderrSink.writeln(kImportUsage);
    return 2;
  }
  return _run(invocation, stdoutSink, stderrSink, env, homeDir);
}

Future<int> _run(
  _ImportInvocation invocation,
  StringSink out,
  StringSink err,
  Map<String, String>? env,
  String? homeDir,
) async {
  final String workdir = invocation.workdir ?? Directory.current.path;
  final OpenCodeSources sources = loadOpenCodeSources(
    workdir: workdir,
    includeGlobal: !invocation.projectOnly,
    includeProject: !invocation.globalOnly,
    env: env,
    homeDir: homeDir,
  );
  for (final String warning in sources.warnings) {
    err.writeln(warning);
  }
  if (sources.isEmpty) {
    out.writeln('没有找到 opencode.json(c)（起点：$workdir）。');
    return 0;
  }
  final OpenCodeImport imported = buildOpenCodeImport(sources);
  for (final String warning in imported.warnings) {
    err.writeln(warning);
  }
  if (imported.isEmpty) {
    out.writeln('没有可导入的字段（agents / commands / providers 等暂不支持）。');
    return 0;
  }
  final String configPath =
      invocation.configPath ?? resolveConfigPath(env: env);
  final File configFile = File(configPath);
  String existing = '';
  try {
    if (configFile.existsSync()) existing = configFile.readAsStringSync();
  } on FileSystemException catch (error) {
    err.writeln('读取配置失败：${error.message}');
    return 2;
  }
  final OpenCodeImportPlan plan;
  try {
    plan = planOpenCodeImport(toml: existing, import: imported);
  } on FormatException catch (error) {
    err.writeln('配置错误：${error.message}');
    return 2;
  }
  for (final String skipped in plan.skipped) {
    err.writeln('跳过：$skipped');
  }
  if (!plan.hasChanges) {
    out.writeln('没有可新增项（已有配置保持不变）。');
    return 0;
  }
  out.writeln('将新增 ${plan.added.length} 项：');
  for (final String item in plan.added) {
    out.writeln('  + $item');
  }
  if (!invocation.write) {
    out.writeln('\n# 将写入 $configPath 的片段（--write 落盘）：');
    out.writeln(plan.snippet);
    return 0;
  }
  try {
    writeConfigFile(configPath, plan.updatedToml);
  } on FileSystemException catch (error) {
    err.writeln('写入失败：${error.message}');
    return 2;
  } on StateError catch (error) {
    err.writeln('写入失败：${error.message}');
    return 2;
  }
  out.writeln('\n已写入 $configPath。');
  return 0;
}

/// 解析结果；参数不合法时 [error] 非空。
class _ImportInvocation {
  const _ImportInvocation({
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

_ImportInvocation? _parse(List<String> args) {
  if (args.isEmpty) return null;
  if (args.first == '--help' || args.first == '-h') {
    return const _ImportInvocation(help: true);
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
        return _ImportInvocation(error: '$arg 缺少路径。');
      }
      final String value = args[++index];
      if (arg == '--config') {
        configPath = value;
      } else {
        workdir = value;
      }
    } else if (arg == '--help' || arg == '-h') {
      return const _ImportInvocation(help: true);
    } else {
      return _ImportInvocation(error: '未知参数：$arg。');
    }
  }
  if (globalOnly && projectOnly) {
    return const _ImportInvocation(
      error: '--global-only 与 --project-only 不能同时使用。',
    );
  }
  return _ImportInvocation(
    write: write,
    globalOnly: globalOnly,
    projectOnly: projectOnly,
    configPath: configPath,
    workdir: workdir,
  );
}
