/// `instructions` 配置项的展开与读取（路径 / glob / URL）。
///
/// 所有来源都按「读不到就当没有」处理：缺失文件、越界符号链接、不可达 URL
/// 一律跳过，绝不因为一条坏配置让整份系统提示装配失败。
library;

import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';

import 'instruction_paths.dart';
import 'instruction_types.dart';
import 'instruction_url.dart';

export 'instruction_paths.dart'
    show expandInstructionHome, isWithinWorkdir, joinInstructionPath;
export 'instruction_types.dart';

/// 把配置项展开成具体来源；相对路径以 [workdir] 为基准，glob 就地展开。
///
/// 展开结果由调用方缓存（一次会话内固定的配置不必每次重 glob）。
List<InstructionTarget> resolveInstructionTargets(
  List<String> entries, {
  required String workdir,
  String? home,
}) {
  final List<InstructionTarget> targets = <InstructionTarget>[];
  for (final String raw in entries) {
    final String entry = raw.trim();
    if (entry.isEmpty) continue;
    final String expanded = expandInstructionHome(entry, home);
    if (expanded.isEmpty) continue;
    if (_isUrl(expanded)) {
      targets.add(InstructionTarget(expanded, remote: true));
    } else if (_isGlob(expanded)) {
      targets.addAll(_expandGlob(expanded, workdir));
    } else {
      final bool absolute = _isAbsolute(expanded);
      targets.add(
        InstructionTarget(
          absolute ? expanded : joinInstructionPath(workdir, expanded),
          guardRoot: absolute ? null : workdir,
        ),
      );
    }
  }
  return targets;
}

/// 依次读取；单条失败跳过，保持配置书写顺序。
///
/// [cache] 按 URL 缓存（含失败结果），保证一次会话内不重复发起网络请求——
/// 工具触发的重新装配因此不会被 5 秒超时拖慢。
Future<List<InstructionDoc>> loadInstructionTargets(
  List<InstructionTarget> targets, {
  Map<String, InstructionDoc?>? cache,
}) async {
  final List<InstructionDoc> docs = <InstructionDoc>[];
  for (final InstructionTarget target in targets) {
    final InstructionDoc? doc = await _loadTarget(target, cache);
    if (doc != null) docs.add(doc);
  }
  return docs;
}

Future<InstructionDoc?> _loadTarget(
  InstructionTarget target,
  Map<String, InstructionDoc?>? cache,
) async {
  if (!target.remote) {
    return readInstructionFile(target.value, target.guardRoot);
  }
  if (cache != null && cache.containsKey(target.value)) {
    return cache[target.value];
  }
  final InstructionDoc? doc = await fetchInstructionUrl(target.value);
  cache?[target.value] = doc;
  return doc;
}

/// 读一个文件并做单文件截断；不存在 / 读失败 / 越界都返回 `null`。
///
/// [direct] 为 true 时要求文件不走符号链接（canonical 与声明路径一致）：项目
/// 祖先目录不在工作区内，不能用 workdir 当 jail，只能禁止重定向。工作目录内
/// 的文件仍按 [guardRoot] 校验 canonical 是否留在 jail 内。
Future<InstructionDoc?> readInstructionFile(
  String path,
  String? guardRoot, {
  bool direct = false,
}) async {
  final File file = File(path);
  if (!file.existsSync()) return null;
  final String canonical;
  try {
    canonical = file.resolveSymbolicLinksSync();
  } on FileSystemException {
    return null;
  }
  if (direct && canonical != path) return null;
  if (guardRoot != null && !isWithinWorkdir(canonical, guardRoot)) return null;
  final String content;
  try {
    content = await file.readAsString();
  } on FileSystemException {
    return null;
  }
  if (content.trim().isEmpty) return null;
  return InstructionDoc(identity: canonical, text: capInstructionText(content));
}

/// 按顺序拼接并施加总量上限；空列表返回 `null`。
String? joinInstructionDocs(List<InstructionDoc> docs) {
  if (docs.isEmpty) return null;
  final StringBuffer buffer = StringBuffer();
  for (final InstructionDoc doc in docs) {
    if (buffer.length >= kInstructionTotalMaxChars) break;
    if (buffer.isNotEmpty) buffer.write('\n\n');
    final int room = kInstructionTotalMaxChars - buffer.length;
    if (doc.text.length <= room) {
      buffer.write(doc.text);
      continue;
    }
    buffer.write(doc.text.substring(0, room > 0 ? room : 0));
    buffer.write(kInstructionTotalTruncated);
    break;
  }
  return buffer.toString();
}

bool _isUrl(String value) =>
    value.startsWith('http://') || value.startsWith('https://');

bool _isGlob(String value) =>
    value.contains('*') || value.contains('?') || value.contains('[');

bool _isAbsolute(String value) =>
    value.startsWith(Platform.pathSeparator) ||
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);

List<InstructionTarget> _expandGlob(String pattern, String workdir) {
  final Glob glob;
  try {
    glob = Glob(pattern);
  } on FormatException {
    return const <InstructionTarget>[];
  }
  final bool absolute = _isAbsolute(pattern);
  try {
    final List<FileSystemEntity> matches =
        glob
            .listSync(root: absolute ? null : workdir, followLinks: false)
            .whereType<File>()
            .toList()
          ..sort(
            (FileSystemEntity a, FileSystemEntity b) =>
                a.path.compareTo(b.path),
          );
    return <InstructionTarget>[
      for (final FileSystemEntity entity in matches)
        InstructionTarget(entity.path, guardRoot: absolute ? null : workdir),
    ];
  } on FileSystemException {
    return const <InstructionTarget>[];
  }
}
