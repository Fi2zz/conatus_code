/// LSP 导航能力：hover / definition / references / document symbols。
library;

import 'lsp_client.dart';
import 'lsp_manager.dart';
import 'lsp_navigation_types.dart';

export 'lsp_navigation_types.dart';

/// 面向工具的导航请求封装。
class LspNavigator {
  const LspNavigator(this.manager);

  final LspManager manager;

  Future<String?> hover(String path, int line, int column) async {
    final LspClient? client = await _client(path);
    if (client == null) return null;
    try {
      await client.ensureDocument(path);
      final Object? result = await client.sendRequest(
        'textDocument/hover',
        <String, Object?>{
          'textDocument': <String, Object?>{'uri': _uri(path)},
          'position': _position(line, column),
        },
      );
      return _hoverText(result is Map ? result['contents'] : null);
    } catch (error) {
      manager.reportError(path, '$error');
      return null;
    }
  }

  Future<List<LspLocation>> definition(
    String path,
    int line,
    int column,
  ) async {
    final Object? result = await _request(path, 'textDocument/definition', line, column);
    return _locations(result);
  }

  Future<List<LspLocation>> references(
    String path,
    int line,
    int column,
  ) async {
    final Object? result = await _request(
      path,
      'textDocument/references',
      line,
      column,
      extra: <String, Object?>{
        'context': <String, Object?>{'includeDeclaration': true},
      },
    );
    return _locations(result);
  }

  Future<List<LspDocumentSymbol>> documentSymbols(String path) async {
    final LspClient? client = await _client(path);
    if (client == null) return const <LspDocumentSymbol>[];
    try {
      await client.ensureDocument(path);
      final Object? result = await client.sendRequest(
        'textDocument/documentSymbol',
        <String, Object?>{'textDocument': <String, Object?>{'uri': _uri(path)}},
      );
      return _symbols(result);
    } catch (error) {
      manager.reportError(path, '$error');
      return const <LspDocumentSymbol>[];
    }
  }

  Future<Object?> _request(
    String path,
    String method,
    int line,
    int column, {
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    final LspClient? client = await _client(path);
    if (client == null) return null;
    try {
      await client.ensureDocument(path);
      return client.sendRequest(
        method,
        <String, Object?>{
          'textDocument': <String, Object?>{'uri': _uri(path)},
          'position': _position(line, column),
          ...extra,
        },
      );
    } catch (error) {
      manager.reportError(path, '$error');
      return null;
    }
  }

  Future<LspClient?> _client(String path) => manager.clientFor(path);

  String _uri(String path) => Uri.file(path).toString();

  Map<String, Object?> _position(int line, int column) => <String, Object?>{
        'line': line > 0 ? line - 1 : 0,
        'character': column > 0 ? column - 1 : 0,
      };

  String? _hoverText(Object? raw) {
    if (raw is String) return raw;
    if (raw is Map) {
      final Object? value = raw['value'] ?? raw['text'];
      return value is String ? value : null;
    }
    if (raw is List) {
      final List<String> parts = <String>[
        for (final Object? item in raw)
          if (_hoverText(item) case final String text) text,
      ];
      return parts.isEmpty ? null : parts.join('\n');
    }
    return null;
  }

  List<LspLocation> _locations(Object? raw) {
    final List<Object?> items = raw is List ? raw : <Object?>[raw];
    final List<LspLocation> locations = <LspLocation>[];
    for (final Object? item in items) {
      if (item is! Map) continue;
      try {
        final Object? uri = item['uri'] ?? item['targetUri'];
        final Object? range = item['range'] ??
            item['targetSelectionRange'] ??
            item['targetRange'];
        final LspLocation? location = _location(uri, range);
        if (location != null) locations.add(location);
      } on FormatException {
        continue;
      }
    }
    return locations;
  }

  LspLocation? _location(Object? uri, Object? range) {
    if (uri is! String || range is! Map) return null;
    final Object? start = range['start'];
    if (start is! Map) return null;
    final int line = (start['line'] as int?) ?? 0;
    final int character = (start['character'] as int?) ?? 0;
    final Object? end = range['end'];
    return LspLocation(
      path: Uri.parse(uri).toFilePath(),
      line: line + 1,
      column: character + 1,
      endLine: end is Map ? ((end['line'] as int?) ?? 0) + 1 : null,
      endColumn: end is Map ? ((end['character'] as int?) ?? 0) + 1 : null,
    );
  }

  List<LspDocumentSymbol> _symbols(Object? raw) {
    if (raw is! List) return const <LspDocumentSymbol>[];
    final List<LspDocumentSymbol> symbols = <LspDocumentSymbol>[];
    for (final Object? item in raw) {
      if (item is! Map) continue;
      final String? name = item['name'] as String?;
      final Object? range = item['range'] ?? item['location'];
      if (name == null || range is! Map) continue;
      final Object? start = range['start'] ?? range['range']?['start'];
      if (start is! Map) continue;
      symbols.add(
        LspDocumentSymbol(
          name: name,
          kind: (item['kind'] as int?) ?? 0,
          line: ((start['line'] as int?) ?? 0) + 1,
          column: ((start['character'] as int?) ?? 0) + 1,
        ),
      );
      final Object? children = item['children'];
      if (children is List) symbols.addAll(_symbols(children));
    }
    return symbols;
  }
}
