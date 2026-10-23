/// `nava harness` 子命令：列出 / 查看 / 对比 / 校验 harness manifest。
///
/// 只读且无副作用：不启动 Agent、不读写项目数据。`--harness` 的装配在入口
/// 装配阶段完成（见 `bin/conatus_code.dart`）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_harness/conatus_harness.dart';

/// 用法文案。
const String kHarnessUsage = '''
用法：nava harness <子命令>
  list [目录]        列出目录下的 manifest（缺省 ./harnesses）
  show <文件>        输出规范化 JSON（键顺序稳定，便于 diff）
  diff <a> <b>       对比两份 manifest
  check <文件>       解析并校验，成功打印摘要（可用于 CI）
''';

/// 执行 harness 子命令，返回进程退出码。
///
/// [args] 是 `harness` 之后的参数；[out] / [err] 可注入以便测试。
Future<int> runHarnessCommand(
  List<String> args, {
  StringSink? out,
  StringSink? err,
}) async {
  final StringSink sink = out ?? stdout;
  final StringSink errors = err ?? stderr;
  if (args.isEmpty) {
    sink.writeln(kHarnessUsage);
    return 2;
  }
  final String verb = args.first;
  final List<String> rest = args.sublist(1);
  switch (verb) {
    case 'help':
    case '--help':
    case '-h':
      sink.writeln(kHarnessUsage);
      return 0;
    case 'list':
      return _list(rest, sink, errors);
    case 'show':
      return _show(rest, sink, errors);
    case 'diff':
      return _diff(rest, sink, errors);
    case 'check':
      return _check(rest, sink, errors);
    default:
      errors.writeln('未知子命令：$verb');
      sink.writeln(kHarnessUsage);
      return 2;
  }
}

int _list(List<String> rest, StringSink out, StringSink err) {
  final Directory dir = Directory(rest.isEmpty ? 'harnesses' : rest.first);
  if (!dir.existsSync()) {
    err.writeln('目录不存在：${dir.path}');
    return 2;
  }
  final List<File> files =
      dir
          .listSync()
          .whereType<File>()
          .where((File file) => file.path.endsWith('.json'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    err.writeln('目录里没有 *.json：${dir.path}');
    return 2;
  }
  int failures = 0;
  for (final File file in files) {
    final HarnessManifest? manifest = _load(file.path, err);
    if (manifest == null) {
      failures++;
      continue;
    }
    out.writeln('${manifest.name}\t${_summary(manifest)}\t${file.path}');
  }
  return failures == 0 ? 0 : 2;
}

int _show(List<String> rest, StringSink out, StringSink err) {
  if (rest.isEmpty) {
    err.writeln('show 需要一个文件路径');
    return 2;
  }
  final HarnessManifest? manifest = _load(rest.first, err);
  if (manifest == null) return 2;
  out.writeln(const JsonEncoder.withIndent('  ').convert(manifest.toJson()));
  return 0;
}

int _diff(List<String> rest, StringSink out, StringSink err) {
  if (rest.length < 2) {
    err.writeln('diff 需要两个文件路径');
    return 2;
  }
  final HarnessManifest? a = _load(rest[0], err);
  final HarnessManifest? b = _load(rest[1], err);
  if (a == null || b == null) return 2;
  final List<String> lines = diffHarness(a, b);
  if (lines.isEmpty) {
    out.writeln('无差异');
    return 0;
  }
  for (final String line in lines) {
    out.writeln(line);
  }
  return 0;
}

int _check(List<String> rest, StringSink out, StringSink err) {
  if (rest.isEmpty) {
    err.writeln('check 需要一个文件路径');
    return 2;
  }
  final HarnessManifest? manifest = _load(rest.first, err);
  if (manifest == null) return 2;
  out.writeln('OK ${manifest.name}：${_summary(manifest)}');
  return 0;
}

HarnessManifest? _load(String path, StringSink err) {
  try {
    final Object? decoded = jsonDecode(File(path).readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      err.writeln('$path：顶层必须是 JSON 对象');
      return null;
    }
    return HarnessManifest.fromJson(decoded);
  } on FileSystemException catch (error) {
    err.writeln('$path：${error.message}');
    return null;
  } on FormatException catch (error) {
    err.writeln('$path：JSON 解析失败（${error.message}）');
    return null;
  }
}

String _summary(HarnessManifest manifest) {
  final Set<String>? allowed = manifest.allowedTools;
  final String tools = allowed == null
      ? 'tools=all'
      : 'tools=${allowed.length}';
  return 'profile=${manifest.profile.name} '
      'effort=${manifest.profile.reasoningEffort} '
      'sections=${manifest.sections.length} '
      'budget=${manifest.profile.budget.finalizeAfter} '
      '$tools';
}
