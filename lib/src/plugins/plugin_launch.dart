/// Node 可执行文件定位与宿主脚本落盘。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'plugin_host_source.dart';

/// 查找 Node：`NAVA_NODE` 优先，其次 PATH 里的 `node`。
Future<String?> resolvePluginNode() async {
  final String? configured = Platform.environment['NAVA_NODE'];
  if (configured != null && configured.trim().isNotEmpty) {
    return configured.trim();
  }
  try {
    final ProcessResult result = await Process.run('which', <String>['node']);
    final String path = '${result.stdout}'.trim();
    return result.exitCode == 0 && path.isNotEmpty ? path : null;
  } on ProcessException {
    return null;
  }
}

/// 把内嵌宿主写到缓存目录；按源码哈希版本化。
Future<String> ensurePluginHostScript({required String homeDir}) async {
  final String hash = sha256
      .convert(utf8.encode(kPluginHostSource))
      .toString()
      .substring(0, 12);
  final Directory dir = Directory('$homeDir/.nava/plugins');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final File file = File('${dir.path}/host-$hash.mjs');
  if (!file.existsSync()) {
    await file.writeAsString(kPluginHostSource, flush: true);
    try {
      await Process.run('chmod', <String>['600', file.path]);
    } on ProcessException {
      // 非 POSIX 平台忽略。
    }
  }
  return file.path;
}
