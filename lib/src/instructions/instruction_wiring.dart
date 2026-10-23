/// 指令层的服务装配与工具后置中间件。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'instruction_loader.dart';

/// 服务键：当前 [InstructionLoader]。
const String kInstructionsService = 'instructions';

/// 读过路径后需要记下沿途 `AGENTS.md` 的工具。
const Set<String> kInstructionNoteTools = <String>{
  'read_file',
  'list_files',
  'rg',
  'glob',
};

/// 提供 `'instructions'` 服务并随上下文释放。
InstructionLoader provideInstructionLoader(
  Context app, {
  required String workdir,
  String? home,
  List<String> extra = const <String>[],
}) {
  final InstructionLoader loader = InstructionLoader(
    workdir: workdir,
    home: home,
    extra: extra,
  );
  app.provide(kInstructionsService, loader);
  app.onDispose(loader.dispose);
  return loader;
}

/// 挂工具后置中间件：调用成功（或失败）后把目标路径交给 [loader]。
///
/// [onNoted] 用来在记下新文件后立即刷新 prompt 快照（可为 `null`）。
Disposer instrumentInstructionNotes(
  Context app,
  InstructionLoader loader, {
  Future<void> Function()? onNoted,
}) => app.tools.use((ToolCall call, Future<ToolResult> Function() next) async {
  final ToolResult result = await next();
  final String? path = instructionNotePath(call);
  if (path != null) {
    await loader.notePath(path);
    await onNoted?.call();
  }
  return result;
}, tag: 'instructions');

/// 从工具调用里取出要记的路径；工具不在名单内或没有 `path` 参数时返回 `null`。
String? instructionNotePath(ToolCall call) {
  if (!kInstructionNoteTools.contains(call.name)) return null;
  final Object? value = call.arguments['path'];
  if (value is! String) return null;
  final String path = value.trim();
  return path.isEmpty ? null : path;
}
