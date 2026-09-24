/// 项目上下文：AGENTS.md / NAVA.md 的读取、拼接与截断。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

/// 建临时目录并在其中写 [files]（`文件名 → 内容`），返回目录路径。
String _dirWith(Map<String, String> files) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-project-ctx');
  addTearDown(() => dir.deleteSync(recursive: true));
  for (final MapEntry<String, String> entry in files.entries) {
    File('${dir.path}${Platform.pathSeparator}${entry.key}')
        .writeAsStringSync(entry.value);
  }
  return dir.path;
}

void main() {
  test('两文件都不存在 → null', () async {
    expect(await loadProjectContext(_dirWith(const <String, String>{})), isNull);
  });

  test('只有 AGENTS.md → 原样返回', () async {
    final String? context =
        await loadProjectContext(_dirWith(<String, String>{'AGENTS.md': '构建：dart test'}));

    expect(context, '构建：dart test');
  });

  test('只有 NAVA.md → 原样返回', () async {
    final String? context =
        await loadProjectContext(_dirWith(<String, String>{'NAVA.md': '本仓库专属约定'}));

    expect(context, '本仓库专属约定');
  });

  test('并存 → AGENTS.md 在前、NAVA.md 在后、空行分隔', () async {
    final String? context = await loadProjectContext(_dirWith(<String, String>{
      'AGENTS.md': 'A 内容',
      'NAVA.md': 'N 内容',
    }));

    expect(context, 'A 内容\n\nN 内容');
  });

  test('超过上限截断并标注', () async {
    final String big = 'x' * (kProjectContextMaxChars + 100);
    final String? context =
        await loadProjectContext(_dirWith(<String, String>{'AGENTS.md': big}));

    expect(context, isNotNull);
    expect(context!.length, lessThanOrEqualTo(kProjectContextMaxChars + 100));
    expect(context, endsWith('（已截断，原文超长）'));
    expect(context, startsWith('x' * kProjectContextMaxChars));
  });

  test('读取失败按空处理（目录路径不存在不抛错）', () async {
    final String missing = '${Directory.systemTemp.path}/nope-${DateTime.now().microsecondsSinceEpoch}';
    expect(await loadProjectContext(missing), isNull);
  });
}
