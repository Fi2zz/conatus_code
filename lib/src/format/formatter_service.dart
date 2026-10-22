/// format-on-edit：模型编辑文件后自动格式化，失败只提示、不失败工具。
///
/// 服务键 `'formatter'`。探针按项目类型决定命令（见 [detectFormatter]），
/// 命令经 `'shell'` 缝执行（沙箱白名单照常生效，被封时降级为提示，绝不绕过
/// 沙箱）。只处理成功的编辑工具结果，最多 [kFormatterMaxFiles] 个文件。
///
/// 装配顺序：在 linter **之后**挂载，即中间件链更内层。框架的内层先完成
/// 后处理，所以 formatter 先改文件、linter 再看到格式化后的内容。
library;

import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import '../config/config_schema.dart';
import '../tools/git_tools.dart';
import 'formatter_path.dart';
import 'formatter_probe.dart';

/// 触发 format-on-edit 的编辑工具。
const Set<String> kFormatterToolNames = <String>{
  'write_file',
  'edit_file',
  'apply_patch',
};

/// 单次最多格式化的文件数；`apply_patch` 可能一次改很多文件。
const int kFormatterMaxFiles = 20;

/// 失败原因回传模型的截断字符数。
const int kFormatterReasonChars = 200;

/// format-on-edit 服务。
class FormatterService {
  FormatterService({
    required ShellExecutor shell,
    required FormatterConfig config,
    required String workdir,
  }) : _shell = shell,
       _config = config,
       _workdir = workdir;

  final ShellExecutor _shell;
  final FormatterConfig _config;
  final String _workdir;

  /// 格式化 [files]（相对工作目录）；返回要追加给模型的提示。
  ///
  /// 成功返回 `null`（不制造噪声）；失败 / 超时 / 沙箱拒绝返回
  /// `[Formatter] skipped: <原因>`。调用方负责保证工具本身仍算成功。
  Future<String?> runIfNeeded(List<String> files) async {
    if (!_config.enabled) return null;
    final List<String> targets = _targets(files);
    if (targets.isEmpty || targets.length > kFormatterMaxFiles) return null;
    final List<String> failures = <String>[];
    for (final String target in targets) {
      final String? failure = await _formatOne(target);
      if (failure != null) failures.add(failure);
    }
    return failures.isEmpty ? null : failures.join('\n');
  }

  /// 归一化、去重并过滤已删除 / 越界 / `.opencode` 的目标。
  List<String> _targets(List<String> files) {
    final List<String> out = <String>[];
    final Set<String> seen = <String>{};
    for (final String path in files) {
      final String? target = resolveFormatterTarget(_workdir, path);
      if (target == null || !seen.add(target)) continue;
      if (!File(target).existsSync()) continue;
      out.add(target);
    }
    return out;
  }

  /// 解析探针；`command` / `extensions` 覆盖时按配置受限。
  FormatterProbe? _probeFor(String target) {
    final List<String> extensions = _config.extensions;
    if (extensions.isNotEmpty &&
        !extensions.contains(formatterExtension(target))) {
      return null;
    }
    if (_config.command != null && extensions.isNotEmpty) {
      return const FormatterProbe(
        name: 'custom',
        extensions: <String>[],
        command: <String>[],
      );
    }
    return detectFormatter(_workdir, target);
  }

  /// 格式化单个目标；返回失败提示，成功返回 `null`。
  Future<String?> _formatOne(String target) async {
    final FormatterProbe? probe = _probeFor(target);
    if (probe == null) return null;
    final String command = _commandFor(probe, target);
    final ShellRunResult result;
    try {
      result = await _shell.run(
        _shell.resolve(
          ShellExecRequest(
            command: command,
            workdir: _workdir,
            timeoutMs: _config.timeoutMs,
          ),
        ),
      );
    } on Object catch (error) {
      return _skipped('$error');
    }
    if (result.timedOut) {
      return _skipped('超时（${result.timeoutMs}ms）');
    }
    if (result.exitCode == 0) return null;
    return _skipped(_reasonOf(result));
  }

  /// 命令模板：`$FILE` 替换为转义后的绝对路径；无占位符时追加在末尾。
  String _commandFor(FormatterProbe probe, String target) {
    final String quoted = gitQuote(target);
    final String? override = _config.command;
    if (override == null) return '${probe.command.join(' ')} $quoted';
    return override.contains(r'$FILE')
        ? override.replaceAll(r'$FILE', quoted)
        : '$override $quoted';
  }

  /// 从 stderr 优先取出失败原因；过长截断，空则回退退出码。
  String _reasonOf(ShellRunResult result) {
    final String text = '${result.stderr.text}\n${result.stdout.text}'.trim();
    if (text.isEmpty) return '退出码 ${result.exitCode ?? 'null'}';
    return text.length > kFormatterReasonChars
        ? text.substring(0, kFormatterReasonChars)
        : text;
  }

  String _skipped(String reason) => '[Formatter] skipped: $reason';

  /// 挂工具中间件：成功的编辑工具返回后格式化，失败只追加提示。
  Disposer mount(ToolRegistry tools) {
    if (!_config.enabled) return () {};
    return tools.use((ToolCall call, Future<ToolResult> Function() next) async {
      final ToolResult result = await next();
      if (result.isError || !kFormatterToolNames.contains(call.name)) {
        return result;
      }
      if (result.value == null && result.content.contains('待定补丁')) {
        return result;
      }
      final String? notice = await runIfNeeded(_editedFiles(call, result));
      if (notice == null) return result;
      return ToolResult.success(
        '${result.content}\n\n$notice',
        value: result.value,
      );
    });
  }

  /// 取出本次改动的文件：单文件在参数里，`apply_patch` 在结果 `files` 里。
  List<String> _editedFiles(ToolCall call, ToolResult result) {
    final Object? single = call.arguments['path'];
    if (single is String && single.isNotEmpty) return <String>[single];
    final Object? value = result.value;
    if (value is! Map<String, Object?>) return const <String>[];
    final Object? files = value['files'];
    if (files is! List) return const <String>[];
    return files.whereType<String>().where((String p) => p.isNotEmpty).toList();
  }
}

/// 装配：注册 `'formatter'` 服务并挂中间件；未启用时零副作用。
FormatterService provideFormatter(
  Context ctx, {
  required FormatterConfig config,
  required String workdir,
  ShellExecutor? shell,
}) {
  final FormatterService formatter = FormatterService(
    shell: shell ?? ctx.require<ShellExecutor>('shell'),
    config: config,
    workdir: workdir,
  );
  ctx.provide('formatter', formatter);
  ctx.effect(() => formatter.mount(ctx.tools));
  return formatter;
}
