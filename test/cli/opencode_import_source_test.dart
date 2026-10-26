/// OpenCode 配置源发现：全局、项目祖先、`.opencode` 与 JSONC。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

Directory _temp() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-oc-src-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

String _path(Directory root, String relative) =>
    '${root.path}${Platform.pathSeparator}'
    '${relative.replaceAll('/', Platform.pathSeparator)}';

void _write(String path, String content) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

void main() {
  test('全局 → 项目直接配置 → .opencode 的顺序', () {
    final Directory home = _temp();
    final Directory project = _temp();
    final Directory nested = Directory(_path(project, 'packages/app'))
      ..createSync(recursive: true);
    _write(
      _path(home, '.config/opencode/opencode.jsonc'),
      '{"model": "global/model"}',
    );
    _write(_path(project, 'opencode.json'), '{"model": "root/model"}');
    _write(_path(nested, 'opencode.json'), '{"model": "nested/model"}');
    _write(
      _path(project, '.opencode/opencode.json'),
      '{"model": "opencode-root/model"}',
    );
    _write(
      _path(nested, '.opencode/opencode.jsonc'),
      '{"model": "opencode-nested/model"}',
    );

    final OpenCodeSources sources = loadOpenCodeSources(
      workdir: nested.path,
      homeDir: home.path,
    );

    expect(
      sources.documents.map((OpenCodeDocument doc) => doc.values['model']),
      <Object?>[
        'global/model',
        'root/model',
        'nested/model',
        'opencode-root/model',
        'opencode-nested/model',
      ],
    );
    expect(sources.warnings, isEmpty);
  });

  test('同目录 json 与 jsonc 都读，jsonc 排后并告警', () {
    final Directory home = _temp();
    final Directory project = _temp();
    _write(_path(project, 'opencode.json'), '{"model": "json/model"}');
    _write(_path(project, 'opencode.jsonc'), '{"model": "jsonc/model"}');

    final OpenCodeSources sources = loadOpenCodeSources(
      workdir: project.path,
      homeDir: home.path,
    );

    expect(
      sources.documents.map((OpenCodeDocument doc) => doc.values['model']),
      <Object?>['json/model', 'jsonc/model'],
    );
    expect(sources.warnings.single, contains('opencode.jsonc'));
  });

  test('坏 JSONC 只告警跳过，不影响其它文件', () {
    final Directory home = _temp();
    final Directory project = _temp();
    _write(_path(project, 'opencode.json'), '{ not json');
    _write(_path(project, '.opencode/opencode.json'), '{"model": "ok/m"}');

    final OpenCodeSources sources = loadOpenCodeSources(
      workdir: project.path,
      homeDir: home.path,
    );

    expect(sources.documents, hasLength(1));
    expect(sources.documents.single.values['model'], 'ok/m');
    expect(sources.warnings.single, contains('opencode.json'));
  });

  test('global-only / project-only 开关', () {
    final Directory home = _temp();
    final Directory project = _temp();
    _write(
      _path(home, '.config/opencode/opencode.json'),
      '{"model": "global/model"}',
    );
    _write(_path(project, 'opencode.json'), '{"model": "project/model"}');

    final OpenCodeSources onlyGlobal = loadOpenCodeSources(
      workdir: project.path,
      homeDir: home.path,
      includeProject: false,
    );
    final OpenCodeSources onlyProject = loadOpenCodeSources(
      workdir: project.path,
      homeDir: home.path,
      includeGlobal: false,
    );

    expect(
      onlyGlobal.documents.single.values['model'],
      'global/model',
    );
    expect(
      onlyProject.documents.single.values['model'],
      'project/model',
    );
  });
}
