/// LSP 导航工具：hover / definition / references / document symbols。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import 'lsp_manager.dart';
import 'lsp_navigation.dart';

/// 位置类工具共用参数。
abstract class _PositionTool extends Tool {
  const _PositionTool(this.navigator, this.manager);

  final LspNavigator navigator;
  final LspManager manager;

  @override
  List<String> get pathParams => const <String>['path'];

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('path', required: true, description: '文件路径'),
        ParamSpec.integer('line', required: true, description: '行号（从 1 开始）'),
        ParamSpec.integer('column', required: true, description: '列号（从 1 开始）'),
      ];

  Future<ToolResult> run(String path, int line, int column);

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String path = ctx.str('path');
    final int line = ctx.integer('line') ?? 1;
    final int column = ctx.integer('column') ?? 1;
    final String? error = manager.errorFor(path);
    if (error != null) {
      return ToolResult.failure(
        'LSP 不可用：$error',
        error: ToolError('LSP_UNAVAILABLE', error),
      );
    }
    return run(path, line, column);
  }

  ToolResult empty(String message) => ToolResult.success(message);
}

/// `lsp_hover`。
class LspHoverTool extends _PositionTool {
  const LspHoverTool(super.navigator, super.manager);

  @override
  String get name => 'lsp_hover';

  @override
  String get description => '查询文件位置的 LSP hover 信息。';

  @override
  Future<ToolResult> run(String path, int line, int column) async {
    final String? text = await navigator.hover(path, line, column);
    return empty(text == null || text.trim().isEmpty ? '没有 hover 信息。' : text);
  }
}

/// `lsp_definition`。
class LspDefinitionTool extends _PositionTool {
  const LspDefinitionTool(super.navigator, super.manager);

  @override
  String get name => 'lsp_definition';

  @override
  String get description => '跳转到符号定义（LSP definition）。';

  @override
  Future<ToolResult> run(String path, int line, int column) async {
    final List<LspLocation> locations =
        await navigator.definition(path, line, column);
    return empty(_formatLocations(locations, '没有定义。'));
  }
}

/// `lsp_references`。
class LspReferencesTool extends _PositionTool {
  const LspReferencesTool(super.navigator, super.manager);

  @override
  String get name => 'lsp_references';

  @override
  String get description => '查找符号引用（LSP references）。';

  @override
  Future<ToolResult> run(String path, int line, int column) async {
    final List<LspLocation> locations =
        await navigator.references(path, line, column);
    return empty(_formatLocations(locations, '没有引用。'));
  }
}

/// `lsp_document_symbols`。
class LspDocumentSymbolsTool extends Tool {
  const LspDocumentSymbolsTool(this.navigator, this.manager);

  final LspNavigator navigator;
  final LspManager manager;

  @override
  String get name => 'lsp_document_symbols';

  @override
  String get description => '列出文件的 LSP 文档符号。';

  @override
  List<String> get pathParams => const <String>['path'];

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('path', required: true, description: '文件路径'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String path = ctx.str('path');
    final String? error = manager.errorFor(path);
    if (error != null) {
      return ToolResult.failure(
        'LSP 不可用：$error',
        error: ToolError('LSP_UNAVAILABLE', error),
      );
    }
    final List<LspDocumentSymbol> symbols =
        await navigator.documentSymbols(path);
    if (symbols.isEmpty) return ToolResult.success('没有文档符号。');
    return ToolResult.success(
      <String>[
        for (final LspDocumentSymbol symbol in symbols)
          '${symbol.line}:${symbol.column} kind=${symbol.kind} ${symbol.name}',
      ].join('\n'),
    );
  }
}

String _formatLocations(List<LspLocation> locations, String emptyText) {
  if (locations.isEmpty) return emptyText;
  return <String>[
    for (final LspLocation location in locations)
      '${location.path}:${location.line}:${location.column}',
  ].join('\n');
}
