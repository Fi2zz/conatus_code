/// LSP 诊断与状态类型。
library;

/// LSP DiagnosticSeverity。
enum LspSeverity { error, warning, information, hint }

/// 一条归一化后的诊断；行/列从 1 开始。
class LspDiagnostic {
  const LspDiagnostic({
    required this.path,
    required this.line,
    required this.column,
    required this.severity,
    required this.message,
    this.code,
  });

  final String path;
  final int line;
  final int column;
  final LspSeverity severity;
  final String message;
  final String? code;

  @override
  String toString() {
    final String codeText = code == null ? '' : ' $code';
    return '$path:$line:$column ${severity.name}$codeText $message';
  }
}

/// 供工具/中间件消费的诊断来源。
abstract interface class LspDiagnosticsSource {
  Future<List<LspDiagnostic>> diagnose(String path);
}
