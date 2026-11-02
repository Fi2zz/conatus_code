/// `nava plugin add|list|remove`：插件包安装与配置写回。
library;

import 'dart:io';

import '../config/config_loader.dart';
import '../config/config_path.dart';
import '../config/config_schema.dart';
import '../config/config_writer.dart';
import 'plugin_config.dart';
import 'plugin_discovery.dart';
import 'plugin_installer.dart';
import 'plugin_toml_edit.dart';
import 'plugin_types.dart';
import 'plugin_usage.dart';

/// 执行 `nava plugin`，返回退出码。
Future<int> runPluginCli(
  List<String> args, {
  StringSink? out,
  StringSink? err,
  String? configPath,
  String? homeDir,
  PluginInstaller? installer,
}) async {
  final StringSink stdoutSink = out ?? stdout;
  final StringSink stderrSink = err ?? stderr;
  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    stdoutSink.writeln(kPluginUsage);
    return args.isEmpty ? 2 : 0;
  }
  String? explicitConfig = configPath;
  String? workdir;
  final List<String> rest = <String>[];
  for (int index = 0; index < args.length; index++) {
    final String arg = args[index];
    if (arg == '--config' && index + 1 < args.length) {
      explicitConfig = args[++index];
    } else if (arg == '--workdir' && index + 1 < args.length) {
      workdir = args[++index];
    } else {
      rest.add(arg);
    }
  }
  if (rest.isEmpty) {
    stdoutSink.writeln(kPluginUsage);
    return 2;
  }
  final String command = rest.first;
  final String path = resolveConfigPath(explicit: explicitConfig);
  final String home = homeDir ?? Platform.environment['HOME'] ?? '.';
  final PluginInstaller tool = installer ?? PluginInstaller(homeDir: home);
  return switch (command) {
    'add' => _add(rest.skip(1).toList(), path, tool, stdoutSink, stderrSink),
    'list' => _list(path, workdir, stdoutSink, stderrSink),
    'remove' => _remove(
      rest.skip(1).toList(),
      path,
      tool,
      stdoutSink,
      stderrSink,
    ),
    'check' || 'update' => _reserved(command, stdoutSink),
    _ => _unknown(command, stderrSink),
  };
}

Future<int> _add(
  List<String> args,
  String configPath,
  PluginInstaller installer,
  StringSink out,
  StringSink err,
) async {
  if (args.isEmpty) {
    err.writeln('用法：nava plugin add <目录|npm/git spec>');
    return 2;
  }
  final String source = args.first;
  final String installSource = isLocalPluginSource(source)
      ? resolveLocalPluginSource(source, base: File(configPath).parent.path)
      : source;
  final PluginInstallResult result = await installer.add(installSource);
  if (!result.ok) {
    err.writeln('安装失败：${result.message}');
    return 1;
  }
  final String file = configPath;
  final String existing = File(file).existsSync()
      ? File(file).readAsStringSync()
      : '';
  final String snippet = pluginTomlSnippet(source);
  final String next = existing.isEmpty || existing.endsWith('\n')
      ? '$existing\n$snippet'
      : '$existing\n\n$snippet';
  writeConfigFile(file, next);
  out.writeln('已添加插件：$source');
  out.writeln('配置：$file');
  if (isLocalPluginSource(source)) {
    out.writeln('本地插件不需要安装，重启 nava 后加载。');
  } else {
    out.writeln('包已安装到 ${installer.installRoot}，重启 nava 后加载。');
  }
  return 0;
}

Future<int> _list(
  String configPath,
  String? workdir,
  StringSink out,
  StringSink err,
) async {
  final ConatusCodeConfig config;
  try {
    config = loadConfig(path: configPath);
  } on ConfigException catch (error) {
    err.writeln('配置错误：${error.message}');
    return 2;
  }
  out.writeln('全局插件（config.toml）：');
  if (config.plugins.isEmpty) {
    out.writeln('  （无）');
  } else {
    for (final PluginConfig plugin in config.plugins) {
      out.writeln('  ${plugin.enabled ? '✓' : '✗'} ${plugin.source}');
    }
  }
  final PluginDiscoveryResult discovery = await PluginDiscovery(
    workdir: workdir ?? Directory.current.path,
  ).discoverProject();
  out.writeln('项目插件（${workdir ?? Directory.current.path}）：');
  if (discovery.candidates.isEmpty) {
    out.writeln('  （无）');
  } else {
    for (final PluginCandidate candidate in discovery.candidates) {
      out.writeln('  ? ${candidate.spec.source}  [${candidate.origin}]');
    }
  }
  for (final String warning in discovery.warnings) {
    err.writeln(warning);
  }
  return 0;
}

Future<int> _remove(
  List<String> args,
  String configPath,
  PluginInstaller installer,
  StringSink out,
  StringSink err,
) async {
  if (args.isEmpty) {
    err.writeln('用法：nava plugin remove <spec> [--purge]');
    return 2;
  }
  final String source = args.first;
  final bool purge = args.contains('--purge');
  final File file = File(configPath);
  if (!file.existsSync()) {
    err.writeln('配置文件不存在：$configPath');
    return 1;
  }
  final String existing = file.readAsStringSync();
  final String next = removePluginBlock(existing, source);
  if (next == existing) {
    err.writeln('没有找到插件：$source');
    return 1;
  }
  writeConfigFile(file.path, next);
  if (purge) {
    final PluginInstallResult result = await installer.remove(source);
    if (!result.ok) err.writeln('卸载失败：${result.message}');
  }
  out.writeln('已移除插件：$source');
  return 0;
}

int _reserved(String command, StringSink out) {
  out.writeln('nava plugin $command 将在 P4.2 实现。');
  return 0;
}

int _unknown(String command, StringSink err) {
  err.writeln('未知子命令：$command');
  err.writeln(kPluginUsage);
  return 2;
}
