/// 把 [InstructionLoader] 接成 system prompt 的 `project` 段。
///
/// 段的文本 provider 每次 assemble 都会触发一次异步重新装配；同步返回最近
/// 一次完成的快照（[PromptSection.text] 是同步签名，不能在这里等待 IO）。
/// 因此工具记下的嵌套文件在下一轮请求即可见。
library;

import 'dart:async';

import 'package:conatus_core/conatus_core.dart' show Disposer;
import 'package:conatus_foundation/conatus_foundation.dart';

import 'instruction_loader.dart';

/// `project` 段与加载器的桥接。
class InstructionPrompt {
  InstructionPrompt({required this.loader, required this.prompt});

  final InstructionLoader loader;
  final SystemPrompt prompt;

  Disposer? _section;

  /// 启动时先装配一次；有内容才注册 `project` 段（避免空段污染提示词）。
  Future<void> start() async {
    await loader.compose();
    _ensureSection();
  }

  /// 重新装配；首次出现内容时补注册。
  Future<void> refresh() async {
    await loader.compose();
    _ensureSection();
  }

  void _ensureSection() {
    if (_section != null || loader.current == null) return;
    _section = prompt.section(
      PromptSection(name: 'project', text: _assembleText),
    );
  }

  String _assembleText() {
    unawaited(loader.compose());
    return loader.current ?? '';
  }
}
