/// 插件安装器：本地目录、bun/npm 选择与包名解析。
library;

import 'dart:io';

import 'package:conatus_code/src/plugins/plugin_installer.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nava-plugin-install');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('本地目录直接成功，不需要 npm', () async {
    final Directory local = Directory('${dir.path}/local')..createSync();
    final PluginInstaller installer = PluginInstaller(
      homeDir: dir.path,
      finder: (String name) async => null,
    );
    final PluginInstallResult result = await installer.add(local.path);
    expect(result.ok, isTrue);
  });

  test('优先 bun，命令写入 installRoot', () async {
    final List<String> calls = <String>[];
    final PluginInstaller installer = PluginInstaller(
      homeDir: dir.path,
      finder: (String name) async => name == 'bun' ? '/usr/bin/bun' : null,
      runner: (String exe, List<String> args, {String? workdir}) async {
        calls.add('$exe ${args.join(' ')}');
        return const PluginCommandResult(0, '', '');
      },
    );
    final PluginInstallResult result = await installer.add('pkg@1.0.0');
    expect(result.ok, isTrue);
    expect(calls.single, startsWith('/usr/bin/bun add pkg@1.0.0'));
    expect(installer.installRoot, contains('.nava/plugins'));
  });

  test('无 bun 时回退 npm install --prefix', () async {
    final List<String> calls = <String>[];
    final PluginInstaller installer = PluginInstaller(
      homeDir: dir.path,
      finder: (String name) async => name == 'npm' ? '/usr/bin/npm' : null,
      runner: (String exe, List<String> args, {String? workdir}) async {
        calls.add('$exe ${args.join(' ')}');
        return const PluginCommandResult(0, '', '');
      },
    );
    final PluginInstallResult result = await installer.add('pkg');
    expect(result.ok, isTrue);
    expect(calls.single, contains('npm install --prefix'));
  });

  test('packageNameOf 处理 scoped / 版本 / git', () {
    expect(packageNameOf('@scope/pkg@1.2.3'), '@scope/pkg');
    expect(packageNameOf('pkg@latest'), 'pkg');
    expect(packageNameOf('pkg'), 'pkg');
    expect(packageNameOf('github:me/repo'), isNull);
  });

  test('packageImportName 把 git spec 还原成包名', () {
    expect(
      packageImportName('superpowers@git+https://github.com/obra/superpowers.git'),
      'superpowers',
    );
    expect(packageImportName('@scope/pkg@1.2.3'), '@scope/pkg');
    expect(packageImportName('github:me/opencode-plugin'), 'opencode-plugin');
    expect(
      packageImportName('git+ssh://git@github.com/me/plugin.git#main'),
      'plugin',
    );
  });
}
