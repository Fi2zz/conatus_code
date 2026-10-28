/// LSP 诊断工具与编辑结果回填中间件。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import 'lsp_types.dart';

/// 把诊断格式化成模型可见文本，限制条数和字符数。
String formatLspDiagnostics(List<LspDiagnostic> diagnostics) {
  final StringBuffer buffer = StringBuffer();
  int count = 0;
  for (final LspDiagnostic item in diagnostics) {
    final String line = item.toString();
    if (buffer.length + line.length + 1 > 4000) break;
    if (count >= 20) break;
    if (count > 0) buffer.writeln();
    buffer.write(line);
    count++;
  }
  return buffer.toString();
}

/// `lsp_diagnostics`：读取一个文件的 LSP 诊断。
class LspDiagnosticsTool extends Tool {
  const LspDiagnosticsTool({required LspDiagnosticsSource source}) : _source = source;

  final LspDiagnosticsSource _source;

  @override
  String get name => 'lsp_diagnostics';

  @override
  String get description => '读取文件的 LSP 诊断（类型错误、警告等）。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<String> get pathParams => const <String>['path'];

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('path', required: true, description: '文件路径'),
        ParamSpec.enumeration(
          'severity',
          const <String>['all', 'error', 'warning', 'information', 'hint'],
          description: '最低/指定严重级别，默认 warning',
        ),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String path = ctx.str('path');
    final String severity = ctx.optional<String>('severity') ?? 'warning';
    List<LspDiagnostic> diagnostics;
    try {
      diagnostics = await _source.diagnose(path);
    } catch (error) {
      return ToolResult.failure(
        'LSP 诊断不可用：$error',
        error: ToolError('LSP_UNAVAILABLE', '$error'),
      );
    }
    diagnostics = _filter(diagnostics, severity);
    if (diagnostics.isEmpty) {
      return ToolResult.success('没有 LSP 诊断。');
    }
    return ToolResult.success(
      formatLspDiagnostics(diagnostics),
      value: <String, Object?>{
        'path': path,
        'count': diagnostics.length,
      },
    );
  }

  List<LspDiagnostic> _filter(List<LspDiagnostic> input, String severity) {
    if (severity == 'all') return input;
    final LspSeverity? wanted = switch (severity) {
      'error' => LspSeverity.error,
      'warning' => LspSeverity.warning,
      'information' => LspSeverity.information,
      'hint' => LspSeverity.hint,
      _ => null,
    };
    if (wanted == null) return input;
    return input
        .where((LspDiagnostic item) => item.severity.index <= wanted.index)
        .toList(growable: false);
  }
}

/// 编辑类工具成功后追加诊断；LSP 出错时保持原结果。
ToolMiddleware lspDiagnosticsMiddleware(LspDiagnosticsSource source) {
  return (ToolCall call, Future<ToolResult> Function() next) async {
    final ToolResult result = await next();
    if (result.isError) return result;
    if (!const <String>{'write_file', 'edit_file', 'apply_patch'}.contains(call.name)) {
      return result;
    }
    final List<String> paths = _paths(result.value);
    if (paths.isEmpty) return result;
    final List<LspDiagnostic> diagnostics = <LspDiagnostic>[];
    for (final String path in paths) {
      try {
        diagnostics.addAll(await source.fileChanged(path));
      } catch (_) {
        // LSP is optional; never fail an edit because diagnostics failed.
      }
    }
    final String text = formatLspDiagnostics(diagnostics);
    if (text.isEmpty) return result;
    return result.withContent('${result.content}\n\nLSP diagnostics:\n$text');
  };
}

List<String> _paths(Object? value) {
  if (value is! Map) return const <String>[];
  final List<String> paths = <String>[];
  final Object? path = value['path'];
  if (path is String && path.isNotEmpty) paths.add(path);
  final Object? files = value['files'];
  if (files is List) {
    for (final Object? item in files) {
      if (item is String && item.isNotEmpty) paths.add(item);
    }
  }
  return paths;
}
