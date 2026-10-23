/// 指令层的共享类型与上限常量。
library;

/// 单个文件 / URL 的最大长度。
///
/// 单位是字符（UTF-16 code unit），沿用旧 `project_context` 的语义；真实文件
/// 字节数可能更大（CJK 占 3 字节），这里保护的是拼进 system prompt 的文本量。
const int kInstructionMaxChars = 16384;

/// 一次 `compose()` 的总长度上限（字符，口径同上）。
const int kInstructionTotalMaxChars = 65536;

/// 单文件截断标注（与旧 `project_context` 一致）。
const String kInstructionTruncated = '\n\n（已截断，原文超长）';

/// 总量截断标注。
const String kInstructionTotalTruncated = '\n\n（总长度已截断）';

/// URL 请求的硬超时（连接、首字节与后续读取各自受限）。
const Duration kInstructionUrlTimeout = Duration(seconds: 5);

/// 一条已加载的指令文档。
class InstructionDoc {
  const InstructionDoc({required this.identity, required this.text});

  /// 去重键：本地文件用 canonical 路径，URL 用原地址。
  final String identity;

  /// 已做单文件截断的正文。
  final String text;
}

/// 一条待读取的来源。
class InstructionTarget {
  const InstructionTarget(this.value, {this.remote = false, this.guardRoot});

  /// 绝对路径或 URL。
  final String value;

  /// 是否走网络。
  final bool remote;

  /// 非 `null` 时文件的 canonical 路径必须落在该根内（防符号链接越界）。
  final String? guardRoot;
}

/// 单文件上限截断。
String capInstructionText(String text) => text.length <= kInstructionMaxChars
    ? text
    : '${text.substring(0, kInstructionMaxChars)}$kInstructionTruncated';
