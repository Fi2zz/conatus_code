/// LSP 诊断与状态类型。
library;

import 'dart:io';

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
  Future<List<LspDiagnostic>> fileChanged(String path);
  String? errorFor(String path);
}

/// LSP 启动或协议失败。
class LspException implements Exception {
  const LspException(this.message);

  final String message;

  @override
  String toString() => 'LspException: $message';
}

/// 根据路径推断 LSP languageId；点文件或目录中的点不参与判断。
String languageIdForPath(String path) {
  final String name = path.split(Platform.pathSeparator).last;
  final int dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return 'plaintext';
  final String extension = name.substring(dot + 1).toLowerCase();
  return switch (extension) {
    'dart' => 'dart',
    'ts' || 'tsx' => 'typescript',
    'js' || 'jsx' || 'mjs' || 'cjs' => 'javascript',
    'py' || 'pyi' => 'python',
    'rs' => 'rust',
    'go' => 'go',
    'c' || 'h' => 'c',
    'cc' || 'cpp' || 'cxx' || 'hpp' || 'hh' => 'cpp',
    'json' || 'jsonc' => 'json',
    'yaml' || 'yml' => 'yaml',
    'md' || 'mdx' => 'markdown',
    'sh' || 'bash' || 'zsh' => 'shellscript',
    'html' => 'html',
    'css' => 'css',
    'scss' => 'scss',
    'swift' => 'swift',
    'rb' => 'ruby',
    'php' => 'php',
    'java' => 'java',
    'kt' || 'kts' => 'kotlin',
    'lua' => 'lua',
    'sql' => 'sql',
    _ => extension,
  };
}

/// 一个 LSP server 的运行状态。
class LspServerStatus {
  const LspServerStatus({
    required this.name,
    required this.state,
    this.error,
    this.diagnosticCount = 0,
    this.capabilities = const <String>[],
  });

  final String name;

  /// `disabled` / `idle` / `running` / `error`。
  final String state;
  final String? error;
  final int diagnosticCount;
  final List<String> capabilities;
}

