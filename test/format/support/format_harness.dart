/// formatter 测试共用替身：临时项目 + 记录命令的 shell 缝。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

/// 建一个临时项目；[files] 的键是相对路径（用 `/` 分隔）。
Directory createProject(String tag, Map<String, String> files) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-format-$tag');
  for (final MapEntry<String, String> entry in files.entries) {
    addFile(dir, entry.key, entry.value);
  }
  return dir;
}

/// 在 [dir] 下写一个文件（自动建父目录）。
void addFile(Directory dir, String relative, String content) {
  final String path =
      '${dir.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

/// 项目里的绝对路径（解析符号链接，与 formatter 的规范拼写一致）。
String absolutePath(Directory dir, String relative) {
  final File file = File(
    '${dir.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}',
  );
  try {
    return file.resolveSymbolicLinksSync();
  } on FileSystemException {
    return file.path;
  }
}

/// 成功结局。
ShellRunResult okResult() => const ShellRunResult(
  exitCode: 0,
  timedOut: false,
  timeoutMs: 10000,
  stdout: CollectedOutput(text: ''),
  stderr: CollectedOutput(text: ''),
);

/// 失败结局；[exitCode] 为 null 模拟沙箱白名单拒绝。
ShellRunResult failureResult({int? exitCode = 1, String stderr = ''}) =>
    ShellRunResult(
      exitCode: exitCode,
      timedOut: false,
      timeoutMs: 10000,
      stdout: const CollectedOutput(text: ''),
      stderr: CollectedOutput(text: stderr),
    );

/// 超时结局。
ShellRunResult timeoutResult() => const ShellRunResult(
  exitCode: null,
  timedOut: true,
  timeoutMs: 10000,
  stdout: CollectedOutput(text: ''),
  stderr: CollectedOutput(text: ''),
);

/// 记录每次命令与请求的 shell 替身。
class RecordingShell implements ShellExecutor {
  RecordingShell([ShellAnswer? answer]) : _answer = answer ?? _ok;

  static ShellRunResult _ok(String _) => okResult();

  final ShellAnswer _answer;
  final List<String> commands = <String>[];
  final List<ShellExecRequest> requests = <ShellExecRequest>[];

  /// 最后一次请求的命令。
  String? get lastCommand => commands.isEmpty ? null : commands.last;

  /// 最后一次请求。
  ShellExecRequest? get lastRequest => requests.isEmpty ? null : requests.last;

  @override
  ShellExecSpec resolve(ShellExecRequest request) {
    requests.add(request);
    return ShellExecSpec(
      command: request.command,
      workdir: request.workdir ?? '',
      timeoutMs: request.timeoutMs ?? 0,
      stdoutMaxBytes: request.stdoutMaxBytes ?? 64000,
      stdin: request.stdin,
      env: request.env,
    );
  }

  @override
  Future<ShellRunResult> run(ShellExecSpec spec) async {
    commands.add(spec.command);
    return _answer(spec.command);
  }

  @override
  Future<ShellProcess> start(ShellExecSpec spec) =>
      throw UnimplementedError('RecordingShell.start');
}

/// shell 替身的应答函数。
typedef ShellAnswer = ShellRunResult Function(String command);

/// 建上下文、挂 formatter 中间件；返回 (app, shell, service)。
(Context, RecordingShell, FormatterService) bootFormatter(
  String workdir, {
  ShellAnswer? answer,
  FormatterConfig config = const FormatterConfig(enabled: true),
}) {
  final Context app = Context.root();
  provideTools(app);
  final RecordingShell shell = RecordingShell(answer);
  final FormatterService service = provideFormatter(
    app,
    config: config,
    workdir: workdir,
    shell: shell,
  );
  return (app, shell, service);
}

/// 注册一个只回显成功的 `write`（不落盘，测试自己建文件）。
void registerWriteFile(Context app, {ToolResult Function()? result}) {
  app.effect(
    () => app.tools.fn(
      'write',
      description: '写文件',
      params: <ParamSpec>[ParamSpec.string('path', required: true)],
      handler: (ToolContext ctx) async =>
          result?.call() ?? ToolResult.success('已写入'),
    ),
  );
}

/// 注册一个返回多文件结果的 `apply_patch`。
void registerApplyPatch(Context app, List<String> files) {
  app.effect(
    () => app.tools.fn(
      'apply_patch',
      description: '应用补丁',
      params: <ParamSpec>[ParamSpec.string('patch', required: true)],
      handler: (ToolContext ctx) async =>
          ToolResult.success('已应用补丁', value: <String, Object?>{'files': files}),
    ),
  );
}

/// 注册一个只回显成功的 `edit`（不落盘，测试自己建文件）。
void registerEditFile(Context app) {
  app.effect(
    () => app.tools.fn(
      'edit',
      description: '编辑文件',
      params: <ParamSpec>[ParamSpec.string('path', required: true)],
      handler: (ToolContext ctx) async => ToolResult.success('已编辑'),
    ),
  );
}
