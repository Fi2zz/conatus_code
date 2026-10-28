/// LSP 诊断工具与编辑中间件。
library;

import 'package:conatus_code/src/lsp/lsp_tool.dart';
import 'package:conatus_code/src/lsp/lsp_types.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

class _Source implements LspDiagnosticsSource {
  _Source(this.diagnostics, {this.fail = false});

  final List<LspDiagnostic> diagnostics;
  final bool fail;

  @override
  Future<List<LspDiagnostic>> diagnose(String path) async {
    if (fail) throw StateError('lsp down');
    return diagnostics;
  }

  @override
  Future<List<LspDiagnostic>> fileChanged(String path) => diagnose(path);
}

const LspDiagnostic _error = LspDiagnostic(
  path: '/tmp/a.dart',
  line: 1,
  column: 2,
  severity: LspSeverity.error,
  message: 'type mismatch',
  code: 'E1',
);

const LspDiagnostic _info = LspDiagnostic(
  path: '/tmp/a.dart',
  line: 3,
  column: 4,
  severity: LspSeverity.information,
  message: 'info',
);

void main() {
  test('工具格式化并按严重级别过滤', () async {
    final LspDiagnosticsTool tool = LspDiagnosticsTool(
      source: _Source(const <LspDiagnostic>[_error, _info]),
    );
    final ToolResult result = await tool.call(
      const ToolContext(ToolCall(name: 'lsp_diagnostics', arguments: <String, Object?>{'path': '/tmp/a.dart'})),
    );

    expect(result.isError, isFalse);
    expect(result.content, contains('type mismatch'));
    expect(result.content, isNot(contains('info')));
  });

  test('severity=all 保留全部', () async {
    final LspDiagnosticsTool tool = LspDiagnosticsTool(
      source: _Source(const <LspDiagnostic>[_error, _info]),
    );
    final ToolResult result = await tool.call(
      const ToolContext(ToolCall(name: 'lsp_diagnostics', arguments: <String, Object?>{'path': '/tmp/a.dart', 'severity': 'all'})),
    );

    expect(result.content, contains('type mismatch'));
    expect(result.content, contains('info'));
  });

  test('工具在 LSP 失败时返回失败', () async {
    final LspDiagnosticsTool tool = LspDiagnosticsTool(
      source: _Source(const <LspDiagnostic>[], fail: true),
    );
    final ToolResult result = await tool.call(
      const ToolContext(ToolCall(name: 'lsp_diagnostics', arguments: <String, Object?>{'path': '/tmp/a.dart'})),
    );

    expect(result.isError, isTrue);
    expect(result.error?.code, 'LSP_UNAVAILABLE');
  });

  test('编辑成功结果追加诊断', () async {
    final ToolMiddleware middleware = lspDiagnosticsMiddleware(
      _Source(const <LspDiagnostic>[_error]),
    );
    final ToolResult result = await middleware(
      const ToolCall(name: 'edit_file', arguments: <String, Object?>{'path': '/tmp/a.dart'}),
      () async => ToolResult.success(
        '已编辑',
        value: <String, Object?>{'path': '/tmp/a.dart'},
      ),
    );

    expect(result.content, contains('已编辑'));
    expect(result.content, contains('LSP diagnostics'));
    expect(result.content, contains('type mismatch'));
    expect(result.value, <String, Object?>{'path': '/tmp/a.dart'});
  });

  test('apply_patch 的 files 列表也会诊断', () async {
    final ToolMiddleware middleware = lspDiagnosticsMiddleware(
      _Source(const <LspDiagnostic>[_error]),
    );
    final ToolResult result = await middleware(
      const ToolCall(name: 'apply_patch'),
      () async => ToolResult.success(
        '已应用',
        value: <String, Object?>{'files': <String>['/tmp/a.dart']},
      ),
    );

    expect(result.content, contains('type mismatch'));
  });

  test('失败结果、未知工具和 LSP 异常都不改变结果', () async {
    final ToolMiddleware middleware = lspDiagnosticsMiddleware(
      _Source(const <LspDiagnostic>[], fail: true),
    );
    final ToolResult failed = ToolResult.failure('bad');
    final ToolResult first = await middleware(
      const ToolCall(name: 'edit_file'),
      () async => failed,
    );
    expect(identical(first, failed), isTrue);

    final ToolResult unknown = await middleware(
      const ToolCall(name: 'read_file'),
      () async => ToolResult.success('ok', value: <String, Object?>{'path': '/tmp/a.dart'}),
    );
    expect(unknown.content, 'ok');

    final ToolResult broken = await middleware(
      const ToolCall(name: 'edit_file'),
      () async => ToolResult.success('ok', value: <String, Object?>{'path': '/tmp/a.dart'}),
    );
    expect(broken.content, 'ok');
  });
}
