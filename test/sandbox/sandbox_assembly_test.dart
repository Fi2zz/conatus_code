import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late String canonical;
  setUp(() {
    root = Directory.systemTemp.createTempSync('conatus-sandbox-assembly');
    canonical = root.resolveSymbolicLinksSync();
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('L1 默认启用、L2 关闭：文件 jail 生效，shell 不注入', () {
    final SandboxLayers layers = resolveSandboxLayers(
      root: canonical,
      settings: const SandboxSettings(enabled: false),
    );

    expect(layers.fs, isA<JailedFileSystem>());
    expect(layers.shell, isNull);
  });

  test('两层都关：全本地实现', () {
    final SandboxLayers layers = resolveSandboxLayers(
      root: canonical,
      settings: const SandboxSettings(enabled: false, fsJail: false),
    );

    expect(layers.fs, isNull);
    expect(layers.shell, isNull);
  });

  test('L2 启用但后端不可用：命令 fail-closed 拒斥，L1 仍生效', () {
    final SandboxLayers layers = resolveSandboxLayers(
      root: canonical,
      settings: const SandboxSettings(),
    );

    expect(layers.fs, isA<JailedFileSystem>());
    expect(layers.shell, isA<RejectingShellExecutor>());
  });

  test('L2 启用且后端可用：沙箱命令执行器，L1 生效', () {
    final SandboxLayers layers = resolveSandboxLayers(
      root: canonical,
      settings: const SandboxSettings(),
      backend: const SandboxBackend(launcherPath: '/fake/launcher'),
    );

    expect(layers.fs, isA<JailedFileSystem>());
    expect(layers.shell, isA<SandboxedShellExecutor>());
  });

  test('L2 启用、L1 关闭：只沙箱命令，文件走本地', () {
    final SandboxLayers layers = resolveSandboxLayers(
      root: canonical,
      settings: const SandboxSettings(fsJail: false),
      backend: const SandboxBackend(launcherPath: '/fake/launcher'),
    );

    expect(layers.fs, isNull);
    expect(layers.shell, isA<SandboxedShellExecutor>());
  });
}
