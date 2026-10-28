/// LSP 导航与工具。
library;

import 'dart:io';

import 'package:conatus_code/src/config/config_schema.dart';
import 'package:conatus_code/src/lsp/lsp_manager.dart';
import 'package:conatus_code/src/lsp/lsp_navigation.dart';
import 'package:conatus_code/src/lsp/lsp_navigation_tools.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-lsp-nav');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

LspManager _manager(Directory work) => LspManager(
      config: LspConfig(
        enabled: true,
        servers: <LspServerConfig>[
          LspServerConfig(
            name: 'fake',
            command: <String>[
              Platform.resolvedExecutable,
              '${Directory.current.path}/test/lsp/fixtures/fake_lsp_server.dart',
            ],
            extensions: const <String>['.dart'],
          ),
        ],
      ),
      workdir: work.path,
    );

void main() {
  test('hover / definition / references / documentSymbols', () async {
    final Directory work = _tempDir();
    final File file = File('${work.path}/a.dart')..writeAsStringSync('a');
    final LspManager manager = _manager(work);
    final LspNavigator navigator = LspNavigator(manager);
    addTearDown(manager.close);

    final List<LspLocation> definitions =
        await navigator.definition(file.path, 1, 1);
    expect(definitions, hasLength(1));
    expect(definitions.single.line, 3);
    expect(definitions.single.column, 4);
    expect(await navigator.references(file.path, 1, 1), hasLength(1));
    expect(await navigator.documentSymbols(file.path), hasLength(1));
  });

  test('未配置扩展名返回空', () async {
    final Directory work = _tempDir();
    final File file = File('${work.path}/a.txt')..writeAsStringSync('a');
    final LspManager manager = _manager(work);
    final LspNavigator navigator = LspNavigator(manager);
    addTearDown(manager.close);

    expect(await navigator.hover(file.path, 1, 1), isNull);
    expect(await navigator.definition(file.path, 1, 1), isEmpty);
    expect(await navigator.documentSymbols(file.path), isEmpty);
  });

  test('导航工具输出结果', () async {
    final Directory work = _tempDir();
    final File file = File('${work.path}/a.dart')..writeAsStringSync('a');
    final LspManager manager = _manager(work);
    final LspNavigator navigator = LspNavigator(manager);
    addTearDown(manager.close);

    final ToolResult hover = await LspHoverTool(navigator, manager).call(
      ToolContext(ToolCall(name: 'lsp_hover', arguments: <String, Object?>{
        'path': file.path,
        'line': 1,
        'column': 1,
      })),
    );
    expect(hover.content, 'fake hover');

    final ToolResult symbols = await LspDocumentSymbolsTool(navigator, manager).call(
      ToolContext(ToolCall(name: 'lsp_document_symbols', arguments: <String, Object?>{
        'path': file.path,
      })),
    );
    expect(symbols.content, contains('fakeSymbol'));
  });
}
