/// `nava plugin` CLI：add / list / remove。
library;

import 'dart:io';

import 'package:conatus_code/src/config/config_loader.dart';
import 'package:conatus_code/src/plugins/plugin_cli.dart';
import 'package:conatus_code/src/plugins/plugin_installer.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late String configPath;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nava-plugin-cli');
    configPath = '${dir.path}/config.toml';
    File(configPath).writeAsStringSync('[agent]\nmax_steps = 8\n');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('add 写入配置，list 能看到，remove 删除', () async {
    Directory('${dir.path}/local').createSync();
    final PluginInstaller installer = PluginInstaller(
      homeDir: dir.path,
      finder: (String name) async => null,
      runner: (String exe, List<String> args, {String? workdir}) async =>
          const PluginCommandResult(0, '', ''),
    );
    final StringBuffer out = StringBuffer();
    final StringBuffer err = StringBuffer();
    expect(
      await runPluginCli(
        <String>['add', './local'],
        out: out,
        err: err,
        configPath: configPath,
        homeDir: dir.path,
        installer: installer,
      ),
      0,
    );
    expect(loadConfig(path: configPath).plugins.single.source, './local');

    out.clear();
    expect(
      await runPluginCli(
        <String>['list'],
        out: out,
        err: err,
        configPath: configPath,
        homeDir: dir.path,
        installer: installer,
      ),
      0,
    );
    expect(out.toString(), contains('./local'));

    out.clear();
    expect(
      await runPluginCli(
        <String>['remove', './local'],
        out: out,
        err: err,
        configPath: configPath,
        homeDir: dir.path,
        installer: installer,
      ),
      0,
    );
    expect(loadConfig(path: configPath).plugins, isEmpty);
  });

  test('未知子命令返回 2', () async {
    expect(
      await runPluginCli(
        <String>['nope'],
        out: StringBuffer(),
        err: StringBuffer(),
        configPath: configPath,
        homeDir: dir.path,
      ),
      2,
    );
  });
}
