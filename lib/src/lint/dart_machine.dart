/// `dart analyze --format=machine` 输出的解析与渲染。
///
/// 该格式每行是管道分隔的定长字段：
/// `SEVERITY|TYPE|CODE|<绝对路径>|<行>|<列>|<长度>|<消息…>`
/// —— 消息本身可能含 `|`，因此从第 8 个字段起用 `|` 连接还原。
///
/// **只看能否解析，不看退出码**：`dart analyze` 的退出码有 0（干净）、3（有诊断）、
/// 64（路径不存在）等多种语义，按码判断会把用法提示当告警回灌给模型。实测混传
/// 一个不存在的路径会整次无输出（`Directory or file doesn't exist` + usage），
/// 所以过滤不存在的路径是调用方的责任，见 `linter.dart`。
library;

import 'dart:convert';
import 'dart:io';

/// 定长字段数（消息从第 8 个开始）。
const int kDartMachineFields = 8;

/// 每个文件最多回灌的诊断条数。
const int kLintMaxPerFile = 10;

/// 一条 `dart analyze --format=machine` 诊断。
class DartDiagnostic {
  const DartDiagnostic({
    required this.severity,
    required this.code,
    required this.path,
    required this.line,
    required this.column,
    required this.message,
  });

  /// `ERROR` / `WARNING` / `INFO`。
  final String severity;

  /// 稳定诊断码，如 `RETURN_OF_INVALID_TYPE`、`UNUSED_ELEMENT`。
  final String code;

  /// 诊断所在的绝对路径（机器格式给的是绝对路径）。
  final String path;

  /// 行号（1-based）。
  final int line;

  /// 列号（1-based）。
  final int column;

  /// 人类可读消息（可能多行）。
  final String message;

  /// 是否是错误（决定排序优先级与计数）。
  bool get isError => severity == 'ERROR';
}

/// 解析 machine 输出；无法识别的行**静默丢弃**（用法提示、多行消息都靠这条兜底）。
List<DartDiagnostic> parseDartMachine(String stdout) {
  final List<DartDiagnostic> out = <DartDiagnostic>[];
  for (final String raw in const LineSplitter().convert(stdout)) {
    final DartDiagnostic? item = _parseLine(raw.trim());
    if (item != null) out.add(item);
  }
  return out;
}

/// 解析单行；字段不足或行列号非数字则返回 `null`。
DartDiagnostic? _parseLine(String line) {
  if (line.isEmpty) return null;
  final List<String> parts = line.split('|');
  if (parts.length < kDartMachineFields) return null;
  final int? lineNo = int.tryParse(parts[4]);
  final int? columnNo = int.tryParse(parts[5]);
  if (lineNo == null || columnNo == null) return null;
  return DartDiagnostic(
    severity: parts[0],
    code: parts[2],
    path: parts[3],
    line: lineNo,
    column: columnNo,
    message: parts.sublist(kDartMachineFields - 1).join('|'),
  );
}

/// 渲染成回灌给模型的文本：按文件分组，错误在前，每文件最多
/// [maxPerFile] 条。空输入返回空串。
String formatDartDiagnostics(
  List<DartDiagnostic> items, {
  required String workdir,
  int maxPerFile = kLintMaxPerFile,
}) {
  final Map<String, List<DartDiagnostic>> byFile = _groupByFile(items, workdir);
  final StringBuffer out = StringBuffer();
  for (final MapEntry<String, List<DartDiagnostic>> entry in byFile.entries) {
    _writeGroup(out, entry, maxPerFile);
  }
  return out.toString().trimRight();
}

/// 按「相对工作目录的路径」归组；绝对化失败时退回原路径。
Map<String, List<DartDiagnostic>> _groupByFile(
  List<DartDiagnostic> items,
  String workdir,
) {
  final Map<String, List<DartDiagnostic>> byFile =
      <String, List<DartDiagnostic>>{};
  for (final DartDiagnostic item in items) {
    final String key = _relativize(item.path, workdir);
    byFile.putIfAbsent(key, () => <DartDiagnostic>[]).add(item);
  }
  return byFile;
}

/// 把绝对路径压成相对工作目录的短路径，失败退回原值。
String _relativize(String absolute, String workdir) {
  final String prefix = '$workdir${Platform.pathSeparator}';
  return absolute.startsWith(prefix) ? absolute.substring(prefix.length) : absolute;
}

/// 写一组（一个文件）的诊断：错误优先、同级按行号升序，超出部分计数。
void _writeGroup(
  StringBuffer out,
  MapEntry<String, List<DartDiagnostic>> entry,
  int maxPerFile,
) {
  final List<DartDiagnostic> sorted = List<DartDiagnostic>.of(entry.value)
    ..sort(_compare);
  final List<DartDiagnostic> shown = sorted.take(maxPerFile).toList();
  out.writeln('\n${entry.key}');
  for (final DartDiagnostic item in shown) {
    out.writeln(
      '  ${item.severity} [${item.line}:${item.column}] '
      '${item.code}: ${item.message}',
    );
  }
  final int hidden = sorted.length - shown.length;
  if (hidden > 0) out.writeln('  …另有 $hidden 条未显示');
}

/// 错误排在警告/提示之前，其余按行号升序。
int _compare(DartDiagnostic a, DartDiagnostic b) {
  if (a.isError != b.isError) return a.isError ? -1 : 1;
  return a.line - b.line;
}
