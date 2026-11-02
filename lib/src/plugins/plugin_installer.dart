/// 插件包安装：优先 bun，回退 npm；本地目录不安装。
library;

import 'dart:convert';
import 'dart:io';

import 'plugin_config.dart';

/// 命令执行结果的最小投影，便于测试注入。
class PluginCommandResult {
  const PluginCommandResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == 0;
}

/// 执行一条命令。
typedef PluginCommandRunner =
    Future<PluginCommandResult> Function(
      String executable,
      List<String> arguments, {
      String? workdir,
    });

/// 查找可执行文件；找不到返回 `null`。
typedef PluginExecutableFinder = Future<String?> Function(String name);

/// 安装结局。
class PluginInstallResult {
  const PluginInstallResult({required this.ok, this.message = ''});

  final bool ok;
  final String message;
}

/// 把 npm/git 插件装到 `~/.nava/plugins`。
class PluginInstaller {
  PluginInstaller({
    required this.homeDir,
    PluginExecutableFinder? finder,
    PluginCommandRunner? runner,
  }) : _finder = finder ?? _defaultFinder,
       _runner = runner ?? _defaultRunner;

  /// 家目录；安装根为 `$homeDir/.nava/plugins`。
  final String homeDir;

  final PluginExecutableFinder _finder;
  final PluginCommandRunner _runner;

  String get installRoot =>
      '$homeDir${Platform.pathSeparator}.nava${Platform.pathSeparator}plugins';

  /// 安装一个包 spec；本地路径直接返回成功。
  Future<PluginInstallResult> add(String source) async {
    if (isLocalPluginSource(source)) {
      final Directory dir = Directory(
        resolveLocalPluginSource(source, base: Directory.current.path),
      );
      return dir.existsSync()
          ? const PluginInstallResult(ok: true)
          : const PluginInstallResult(ok: false, message: '本地插件目录不存在');
    }
    final String? bun = await _finder('bun');
    if (bun != null) {
      return _runInstall(bun, <String>['add', source]);
    }
    final String? npm = await _finder('npm');
    if (npm != null) {
      return _runInstall(npm, <String>[
        'install',
        '--prefix',
        installRoot,
        source,
      ]);
    }
    return const PluginInstallResult(
      ok: false,
      message: '需要 bun 或 npm 才能安装插件包',
    );
  }

  /// 卸载一个包；本地路径直接返回成功。
  Future<PluginInstallResult> remove(String source) async {
    if (isLocalPluginSource(source)) {
      return const PluginInstallResult(ok: true);
    }
    final String? bun = await _finder('bun');
    if (bun != null) return _runInstall(bun, <String>['remove', source]);
    final String? npm = await _finder('npm');
    if (npm != null) {
      return _runInstall(npm, <String>[
        'uninstall',
        '--prefix',
        installRoot,
        source,
      ]);
    }
    return const PluginInstallResult(
      ok: false,
      message: '需要 bun 或 npm 才能卸载插件包',
    );
  }

  /// 包是否已安装（按 node_modules 下的包名判断）。
  bool installed(String source) {
    if (isLocalPluginSource(source)) return true;
    final String? name = packageNameOf(source);
    if (name == null) return false;
    return Directory('$installRoot/node_modules/$name').existsSync();
  }

  Future<PluginInstallResult> _runInstall(
    String executable,
    List<String> arguments,
  ) async {
    final Directory dir = Directory(installRoot);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final File manifest = File('$installRoot/package.json');
    if (!manifest.existsSync()) {
      await manifest.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{'private': true, 'type': 'module'})}\n',
      );
    }
    final PluginCommandResult result = await _runner(
      executable,
      arguments,
      workdir: installRoot,
    );
    if (result.ok) return const PluginInstallResult(ok: true);
    final String detail = result.stderr.trim().isEmpty
        ? result.stdout.trim()
        : result.stderr.trim();
    return PluginInstallResult(
      ok: false,
      message: detail.isEmpty ? '安装命令退出码 ${result.exitCode}' : detail,
    );
  }

  static Future<String?> _defaultFinder(String name) async {
    try {
      final ProcessResult result = await Process.run('which', <String>[name]);
      final String path = '${result.stdout}'.trim();
      return result.exitCode == 0 && path.isNotEmpty ? path : null;
    } on ProcessException {
      return null;
    }
  }

  static Future<PluginCommandResult> _defaultRunner(
    String executable,
    List<String> arguments, {
    String? workdir,
  }) async {
    final ProcessResult result = await Process.run(
      executable,
      arguments,
      workingDirectory: workdir,
    );
    return PluginCommandResult(
      result.exitCode,
      '${result.stdout}',
      '${result.stderr}',
    );
  }
}

/// 从 npm/git spec 里取包名；无法判断返回 `null`。
String? packageNameOf(String source) {
  final String value = source.trim();
  if (value.startsWith('@')) {
    final int slash = value.indexOf('/');
    if (slash < 0) return null;
    final int at = value.indexOf('@', slash);
    return at < 0 ? value : value.substring(0, at);
  }
  if (value.startsWith('git') ||
      value.startsWith('github:') ||
      value.startsWith('http')) {
    return null;
  }
  final int at = value.indexOf('@');
  return at <= 0 ? value : value.substring(0, at);
}
