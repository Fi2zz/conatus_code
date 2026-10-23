/// 项目上下文文件（`AGENTS.md` / `NAVA.md`）的兼容入口。
///
/// v2 的层级加载在 `src/instructions/`（[InstructionLoader]）；这里保留
/// [loadProjectContext] 作为薄包装，供仍按「只读工作目录根」语义调用的旧代码
/// 与测试使用（关闭用户级全局文件，避免把本机 `~/.nava` 内容带进单元测试）。
library;

import '../instructions/instruction_loader.dart';
import '../instructions/instruction_source.dart'
    show kInstructionMaxChars;

/// 单个上下文文件的最大字符数（旧名，等同 [kInstructionMaxChars]）。
const int kProjectContextMaxChars = kInstructionMaxChars;

/// 读工作目录根的项目上下文；无内容时返回 `null`。
///
/// 顺序与旧版一致：`AGENTS.md` 在前、`NAVA.md` 在后；符号链接指向工作区外时
/// 一律不读（见 `instruction_source.dart` 的越界校验）。
Future<String?> loadProjectContext(String workdir) async {
  final InstructionLoader loader = InstructionLoader(
    workdir: workdir,
    includeGlobal: false,
  );
  try {
    return await loader.compose();
  } finally {
    loader.dispose();
  }
}
