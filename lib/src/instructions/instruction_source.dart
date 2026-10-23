/// `instructions` 配置项的展开与读取（路径 / glob / URL）。
///
/// 所有来源都按「读不到就当没有」处理：缺失文件、越界符号链接、不可达 URL
/// 一律跳过，绝不因为一条坏配置让整份系统提示装配失败。
library;

import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';

import 'instruction_paths.dart';
import 'instruction_url.dart';

export 'instruction_paths.dart'
    show expandInstructionHome, isWithinWorkdir, joinInstructionPath;

/// 单个文件 / URL 的最大字符数；超限截断并标注。
const int kInstructionMaxChars = 16384;

/// 一次 `compose()` 的总字符上限；超限截断并标注。
const int kInstructionTotalMaxChars = 65536;

/// 单文件截断标注（与旧 `project_context` 一致）。
const String kInstructionTruncated = '\n\n（已截断，原文超长）';

/// 总量截断标注。
const String kInstructionTotalTruncated = '\n\n（总长度已截断）';

/// URL 请求的硬超时（连接、首字节与后续读取各自受限）。
const Duration kInstructionUrlTimeout = Duration(seconds: 5);

/// 一条已加载的指令文档。
class InstructionDoc {
  const InstructionDoc({required this.identity, required this.text});

  /// 去重键：本地文件用 canonical 路径，URL 用原地址。
  final String identity;

  /// 已做单文件截断的正文。
  final String text;
}

/// 一条待读取的来源。
class InstructionTarget {
  const InstructionTarget(this.value, {this.remote = false, this.guardRoot});

  /// 绝对路径或 URL。
  final String value;

  /// 是否走网络。
  final bool remote;

  /// 非 `null` 时文件的 canonical 路径必须落在该根内（防符号链接越界）。
  final String? guardRoot;
}

/// 把配置项展开成具体来源；相对路径以 [workdir] 为基准，glob 就地展开。
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
Future<List<InstructionDoc>> loadInstructionTargets(
  List<InstructionTarget> targets,
) async {
  final List<InstructionDoc> docs = <InstructionDoc>[];
  for (final InstructionTarget target in targets) {
    final InstructionDoc? doc = target.remote
        ? await fetchInstructionUrl(target.value)
        : await readInstructionFile(target.value, target.guardRoot);
    if (doc != null) docs.add(doc);
  }
  return docs;
}

/// 读一个文件并做单文件截断；不存在 / 读失败 / 越界都返回 `null`。
Future<InstructionDoc?> readInstructionFile(
  String path,
  String? guardRoot,
) async {
  final File file = File(path);
  if (!file.existsSync()) return null;
  final String canonical;
  try {
    canonical = file.resolveSymbolicLinksSync();
  } on FileSystemException {
    return null;
  }
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

/// 单文件上限截断。
String capInstructionText(String text) => text.length <= kInstructionMaxChars
    ? text
    : '${text.substring(0, kInstructionMaxChars)}$kInstructionTruncated';

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
