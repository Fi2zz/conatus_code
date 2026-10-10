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
    File(
      '${dir.path}${Platform.pathSeparator}${entry.key}',
    ).writeAsStringSync(entry.value);
  }
  return dir.path;
}

void main() {
  test('两文件都不存在 → null', () async {
    expect(
      await loadProjectContext(_dirWith(const <String, String>{})),
      isNull,
    );
  });

  test('只有 AGENTS.md → 原样返回', () async {
    final String? context = await loadProjectContext(
      _dirWith(<String, String>{'AGENTS.md': '构建：dart test'}),
    );

    expect(context, '构建：dart test');
  });

  test('只有 NAVA.md → 原样返回', () async {
    final String? context = await loadProjectContext(
      _dirWith(<String, String>{'NAVA.md': '本仓库专属约定'}),
    );

    expect(context, '本仓库专属约定');
  });

  test('并存 → AGENTS.md 在前、NAVA.md 在后、空行分隔', () async {
    final String? context = await loadProjectContext(
      _dirWith(<String, String>{'AGENTS.md': 'A 内容', 'NAVA.md': 'N 内容'}),
    );

    expect(context, 'A 内容\n\nN 内容');
  });

  test('超过上限截断并标注', () async {
    final String big = 'x' * (kProjectContextMaxChars + 100);
    final String? context = await loadProjectContext(
      _dirWith(<String, String>{'AGENTS.md': big}),
    );

    expect(context, isNotNull);
    expect(context!.length, lessThanOrEqualTo(kProjectContextMaxChars + 100));
    expect(context, endsWith('（已截断，原文超长）'));
    expect(context, startsWith('x' * kProjectContextMaxChars));
  });

  test('读取失败按空处理（目录路径不存在不抛错）', () async {
    final String missing =
        '${Directory.systemTemp.path}/nope-${DateTime.now().microsecondsSinceEpoch}';
    expect(await loadProjectContext(missing), isNull);
  });

  test('符号链接指向工作区外 → 不读取（防注入并外发）', () async {
    if (Platform.isWindows) return; // symlink 需权限
    final Directory dir = Directory.systemTemp.createTempSync(
      'nava-project-ctx',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final Directory outside = Directory.systemTemp.createTempSync(
      'nava-ctx-out',
    );
    addTearDown(() => outside.deleteSync(recursive: true));
    final String secret = '${outside.path}${Platform.pathSeparator}config.toml';
    File(secret).writeAsStringSync('api_key = "sk-should-not-leak"');
    Link('${dir.path}${Platform.pathSeparator}AGENTS.md').createSync(secret);

    expect(await loadProjectContext(dir.path), isNull);
  });

  test('外链与真实文件并存 → 只返回工作区内那份', () async {
    if (Platform.isWindows) return;
    final Directory dir = Directory.systemTemp.createTempSync(
      'nava-project-ctx',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final Directory outside = Directory.systemTemp.createTempSync(
      'nava-ctx-out',
    );
    addTearDown(() => outside.deleteSync(recursive: true));
    final String secret = '${outside.path}${Platform.pathSeparator}id_rsa';
    File(secret).writeAsStringSync('PRIVATE KEY');
    Link('${dir.path}${Platform.pathSeparator}AGENTS.md').createSync(secret);
    File(
      '${dir.path}${Platform.pathSeparator}NAVA.md',
    ).writeAsStringSync('本仓库约定');

    expect(await loadProjectContext(dir.path), '本仓库约定');
  });

  test('工作区内的符号链接照常读取（未越界）', () async {
    if (Platform.isWindows) return;
    final Directory dir = Directory.systemTemp.createTempSync(
      'nava-project-ctx',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    File(
      '${dir.path}${Platform.pathSeparator}REAL.md',
    ).writeAsStringSync('真实内容');
    Link(
      '${dir.path}${Platform.pathSeparator}AGENTS.md',
    ).createSync('${dir.path}${Platform.pathSeparator}REAL.md');

    expect(await loadProjectContext(dir.path), '真实内容');
  });
}
