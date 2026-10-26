/// `nava import opencode`：把 OpenCode 配置映射进 nava config.toml。
///
/// 默认 dry-run，只打印将新增的片段；`--write` 才原子落盘。项目配置不会在
/// 启动时自动生效——这是显式导入，不是运行时合并。
library;

import 'dart:io';

import '../config/config_path.dart';
import '../config/config_writer.dart';
import 'opencode_import_args.dart';
import 'opencode_import_files.dart';
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

支持：model / default_agent / mcp.servers / permissions / instructions，
      agents / commands（物化为 .nava/agents 与 .nava/commands 下的 Markdown）。
providers / plugins / lsp / references / policies / formatter / tools /
skills 暂不支持，会列出告警。''';

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
  final ImportInvocation? invocation = parseImportArgs(args);
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
  ImportInvocation invocation,
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
    out.writeln('opencode 配置里没有可导入的字段（model / mcp / permissions / agents / commands / instructions）。');
    return 0;
  }
  final DefinitionFilePlan filePlan = planOpenCodeDefinitionFiles(
    import: imported,
    workdir: workdir,
    homeDir: homeDir,
  );
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
  for (final String skipped in <String>[...plan.skipped, ...filePlan.skipped]) {
    err.writeln('跳过：$skipped');
  }
  if (!plan.hasChanges && !filePlan.hasChanges) {
    out.writeln('没有可新增项（已有配置保持不变）。');
    return 0;
  }
  final List<String> added = <String>[
    ...plan.added,
    for (final ImportedDefinitionFile file in filePlan.files) file.label,
  ];
  out.writeln('将新增 ${added.length} 项：');
  for (final String item in added) {
    out.writeln('  + $item');
  }
  if (!invocation.write) {
    if (plan.hasChanges) {
      out.writeln('\n# 将写入 $configPath 的片段（--write 落盘）：');
      out.writeln(plan.snippet);
    }
    for (final ImportedDefinitionFile file in filePlan.files) {
      out.writeln('\n# ${file.path}\n${file.content}');
    }
    return 0;
  }
  try {
    if (plan.hasChanges) writeConfigFile(configPath, plan.updatedToml);
    for (final ImportedDefinitionFile file in filePlan.files) {
      writeFileAtomic(file.path, file.content);
    }
  } on FileSystemException catch (error) {
    err.writeln('写入失败：${error.message}');
    return 2;
  } on StateError catch (error) {
    err.writeln('写入失败：${error.message}');
    return 2;
  }
  out.writeln('\n已写入 ${plan.added.length} 项配置与 ${filePlan.files.length} 个定义文件。');
  return 0;
}
