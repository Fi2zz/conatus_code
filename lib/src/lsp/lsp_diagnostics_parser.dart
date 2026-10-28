/// publishDiagnostics 参数 → 归一化诊断。
library;

import 'lsp_types.dart';

List<LspDiagnostic> parseLspDiagnostics(
  String uri,
  Map<dynamic, dynamic> params,
) {
  final String path = Uri.parse(uri).toFilePath();
  final Object? raw = params['diagnostics'];
  if (raw is! List) return const <LspDiagnostic>[];
  return <LspDiagnostic>[
    for (final Object? item in raw)
      if (item is Map)
        LspDiagnostic(
          path: path,
          line: _startValue(item, 'line') + 1,
          column: _startValue(item, 'character') + 1,
          severity: _severity(item['severity']),
          message: '${item['message'] ?? ''}',
          code: item['code']?.toString(),
        ),
  ];
}

int _startValue(Map<dynamic, dynamic> item, String key) {
  final Object? range = item['range'];
  if (range is! Map) return 0;
  final Object? start = range['start'];
  if (start is! Map) return 0;
  final Object? value = start[key];
  return value is int ? value : 0;
}

LspSeverity _severity(Object? value) {
  final int? code = value is int ? value : null;
  return switch (code) {
    1 => LspSeverity.error,
    2 => LspSeverity.warning,
    3 => LspSeverity.information,
    4 => LspSeverity.hint,
    _ => LspSeverity.information,
  };
}
