/// LSP 导航结果类型。
library;

/// 一个跳转位置；行/列从 1 开始。
class LspLocation {
  const LspLocation({
    required this.path,
    required this.line,
    required this.column,
    this.endLine,
    this.endColumn,
  });

  final String path;
  final int line;
  final int column;
  final int? endLine;
  final int? endColumn;

  @override
  String toString() => '$path:$line:$column';
}

/// 一个文档符号。
class LspDocumentSymbol {
  const LspDocumentSymbol({
    required this.name,
    required this.kind,
    required this.line,
    required this.column,
  });

  final String name;
  final int kind;
  final int line;
  final int column;
}

