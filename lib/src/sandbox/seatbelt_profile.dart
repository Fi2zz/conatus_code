/// Seatbelt profile 构建：deny-default 基线 + 参数化可写根。
///
/// 与 OpenAI Codex CLI 的 seatbelt 策略同形（`(deny default)` 基线、可写根
/// 经 `-D` 参数注入、`/dev/null` 按字符设备放行），mach-lookup 收敛为系统
/// 服务白名单。所有路径经 [buildSandboxParams] 消毒后以 `-D` 参数传入，
/// 不在 profile 文本中做字符串插值，避免路径元字符注入（参考 Claude Code
/// 曾因 workspace 路径含 glob 元字符导致 profile 注入的逃逸事件）。
library;

import 'dart:io';

import 'sandbox_probe.dart';

/// mach-lookup 白名单：系统守护进程，不含文件写代理类服务。
const List<String> seatbeltMachAllowlist = <String>[
  'com.apple.bsd.dirhelper',
  'com.apple.system.opendirectoryd.libinfo',
  'com.apple.system.opendirectoryd.membership',
  'com.apple.cfprefsd.daemon',
  'com.apple.cfprefsd.agent',
  'com.apple.system.logger',
  'com.apple.trustd.agent',
  'com.apple.ocspd',
  'com.apple.SecurityServer',
  'com.apple.networkd',
  'com.apple.SystemConfiguration.DNSConfiguration',
  'com.apple.SystemConfiguration.configd',
];

/// sysctl-read 白名单。
///
/// 实测：本机（macOS 25/26）上带 `sysctl-name` 过滤的规则无法匹配 mib 形式的
/// sysctl 查询（`uname`、部分构建脚本会踩），故只读放开全部 sysctl；敏感进程
/// 信息由 `process-info`（same-sandbox）另行约束。
const String _sysctlRule = '(allow sysctl-read)';

/// 缺省可写缓存目录模板（`~` 在构建时按 HOME 展开）。
const List<String> _cacheTemplates = <String>[
  '~/.pub-cache', '~/.dart_tool', '~/.dart-tool', '~/.npm', '~/.cache',
  '~/.gradle', '~/.m2', '~/.cargo', '~/.rustup', '~/.bun', '~/.deno',
  '~/.local/share', '~/Library/Caches',
];

/// 网络放行时追加的 mach 服务：DNS 解析经 mDNSResponder（XPC）。
const List<String> _networkMachNames = <String>[
  'com.apple.mDNSResponder',
];

/// 展开 `~` 后的缺省可写缓存目录集合。
Set<String> defaultWritableCaches() {
  final String home = Platform.environment['HOME'] ?? '';
  return <String>{
    for (final String raw in _cacheTemplates) _expandHome(raw, home),
  };
}

String _expandHome(String raw, String home) {
  if (!raw.startsWith('~/')) return raw;
  return '$home/${raw.substring(2)}';
}

/// 组装 Seatbelt profile；可写根数量为 [writableCount]（对应 `W0..Wn` 参数）。
String buildSeatbeltProfile({
  required bool networkAllowed,
  required int writableCount,
}) {
  final StringBuffer sb = StringBuffer()
    ..writeln('(version 1)')
    ..writeln('(deny default)')
    ..writeln('(allow process-exec)')
    ..writeln('(allow process-fork)')
    ..writeln('(allow signal (target same-sandbox))')
    ..writeln('(allow process-info* (target same-sandbox))')
    ..writeln('(allow user-preference-read)')
    ..writeln(_sysctlRule)
    ..writeln('(allow ipc-posix-shm)')
    ..writeln('(allow ipc-posix-sem)')
    ..writeln('(allow pseudo-tty)')
    ..writeln(_machBlock(networkAllowed))
    ..writeln('(allow file-read* (subpath "/"))')
    ..writeln(_fileMapExecutableRule())
    ..writeln(_charDeviceRule('/dev/null'))
    ..writeln(_charDeviceRule('/dev/zero'))
    ..writeln(_writableBlock(writableCount))
    ..writeln(networkAllowed ? '(allow network*)' : '(deny network*)');
  return sb.toString();
}

/// 生成 `-D` 参数；每个可写路径先消毒（拒绝引号/括号/反斜杠/glob 元字符）。
List<String> buildSandboxParams({
  required String root,
  required List<String> writablePaths,
}) {
  final List<String> params = <String>['-DROOT=${_sanitize(root)}'];
  for (int i = 0; i < writablePaths.length; i++) {
    params.add('-DW$i=${_sanitize(writablePaths[i])}');
  }
  return params;
}

/// 消毒：路径含 profile 元字符时抛 [SandboxException]（fail-closed）。
String _sanitize(String path) {
  final bool hasMeta = RegExp(r'["()\\*?\[\]{}]').hasMatch(path);
  if (hasMeta) throw SandboxException('沙箱路径含非法元字符：$path');
  return path;
}

/// 允许把文件映射为可执行页：Dart AOT snapshot / JIT 需要；沙箱本就不以
/// 代码执行为门禁（process-exec 全放行），此规则不构成额外弱化。
String _fileMapExecutableRule() => '(allow file-map-executable (subpath "/"))';

String _machBlock(bool networkAllowed) {
  final List<String> names = List<String>.of(seatbeltMachAllowlist);
  if (networkAllowed) names.addAll(_networkMachNames);
  final String entries =
      names.map((String n) => '(global-name "$n")').join('\n  ');
  return '(allow mach-lookup\n  $entries)';
}

String _charDeviceRule(String path) => '(allow file-write-data (require-all '
    '(path "$path") (vnode-type CHARACTER-DEVICE)))';

String _writableBlock(int writableCount) {
  final StringBuffer sb =
      StringBuffer('(allow file-write* (subpath (param "ROOT"))');
  for (int i = 0; i < writableCount; i++) {
    sb.write(' (subpath (param "W$i"))');
  }
  sb.write(' (subpath "/private/tmp") (subpath "/tmp")'
      ' (subpath "/private/var/folders") (subpath "/var/tmp"))');
  return sb.toString();
}
