/// 模型档案预热：交互式启动不解析 models.dev 缓存，首帧后再热身。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_code/providers.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-warmup');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// 写一份合法且新鲜的 models.dev 缓存（create 按 configPath 同目录找它）。
void _writeCache(Directory dir) {
  File('${dir.path}${Platform.pathSeparator}models.dev.json').writeAsStringSync(
    jsonEncode(<String, Object?>{
      'test': <String, Object?>{
        'models': <String, Object?>{
          'm1': <String, Object?>{
            'id': 'm1',
            'limit': <String, Object?>{'context': 32000},
          },
        },
      },
    }),
  );
}

Future<ConatusTuiRuntime> _create(
  Directory dir, {
  required bool interactive,
}) =>
    ConatusTuiRuntime.create(
      baseDir: dir.path,
      sessionDir: dir.path,
      memoryFile: '${dir.path}/memory.json',
      workdir: dir.path,
      configPath: '${dir.path}/config.toml',
      webTools: false,
      skills: false,
      llm: FallbackLlm(const <LlmProvider>[]),
      interactive: interactive,
    );

Future<void> _until(bool Function() predicate) async {
  for (int i = 0; i < 100; i++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('等待条件超时');
}

void main() {
  test('交互式：装配期不解析缓存，startModelWarmup 才热身', () async {
    final Directory dir = _tempDir();
    _writeCache(dir);
    final ConatusTuiRuntime runtime = await _create(dir, interactive: true);
    addTearDown(runtime.dispose);
    final ModelProfileStore store = runtime.app.require<ModelProfileStore>(
      'modelProfiles',
    );

    expect(store.warmed, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(store.warmed, isFalse, reason: '首帧前不该解析 5MB 级缓存');

    runtime.startModelWarmup();
    await _until(() => store.warmed);
    expect(store.profileOf('test', 'm1')?.contextLength, 32000);
  });

  test('headless：装配期直接热身（没有首帧可等）', () async {
    final Directory dir = _tempDir();
    _writeCache(dir);
    final ConatusTuiRuntime runtime = await _create(dir, interactive: false);
    addTearDown(runtime.dispose);

    final ModelProfileStore store = runtime.app.require<ModelProfileStore>(
      'modelProfiles',
    );
    await _until(() => store.warmed);
  });
}
