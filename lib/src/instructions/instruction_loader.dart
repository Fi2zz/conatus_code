/// AGENTS.md 层级加载器：全局 → 项目 → 嵌套 → `instructions`。
///
/// 顺序：`~/.nava/AGENTS.md`、`~/.config/opencode/AGENTS.md`（只读兼容），
/// 项目根到工作目录逐层（每层 `AGENTS.md` 在前、`NAVA.md` 在后），
/// [notePath] 记下的嵌套文件（最近优先），最后是 `instructions` 配置项。
/// 全程按 canonical 路径去重，单文件与总量都有截断上限。
library;

import 'dart:async';
import 'dart:io';

import 'instruction_paths.dart';
import 'instruction_source.dart';

/// 项目层每个目录读取的文件名（顺序即拼接顺序）。
const List<String> kInstructionFileNames = <String>['AGENTS.md', 'NAVA.md'];

/// 层级指令加载器；一个实例对应一次会话（`notePath` 的去重状态是持久的）。
class InstructionLoader {
  InstructionLoader({
    required String workdir,
    String? home,
    List<String> extra = const <String>[],
    bool includeGlobal = true,
  }) : _workdir = canonicalDir(workdir),
       _home = _resolveHome(home),
       _extra = List<String>.unmodifiable(extra),
       _includeGlobal = includeGlobal;

  final String _workdir;
  final String? _home;
  final List<String> _extra;

  /// 是否读取用户级全局文件；兼容包装（`loadProjectContext`）关闭它。
  final bool _includeGlobal;

  final Set<String> _known = <String>{};
  final List<InstructionDoc> _nested = <InstructionDoc>[];
  String? _cached;
  Future<String?>? _running;
  bool _disposed = false;

  /// 最近一次 [compose] 的结果（供同步 prompt 段读取）。
  String? get current => _disposed ? null : _cached;

  /// 重新装配全部层级；没有可读内容时返回 `null`。
  ///
  /// 并发调用合并到同一趟（prompt 每次 assemble 都会触发一次）；完成后再调用
  /// 即可拿到新结果。
  Future<String?> compose() {
    if (_disposed) return Future<String?>.value();
    final Future<String?>? running = _running;
    if (running != null) return running;
    final Future<String?> future = _safeCompose();
    _running = future.whenComplete(() => _running = null);
    return _running!;
  }

  /// prompt 段用 `unawaited` 触发重新装配，异常不能变成未处理的异步错误。
  Future<String?> _safeCompose() async {
    try {
      return await _compose();
    } on Exception {
      return _cached;
    }
  }

  /// 记下 [path] 到工作目录之间所有 `AGENTS.md`（最近优先），每个文件只读一次。
  ///
  /// 只读不写；目标在 [workdir] 外时直接忽略（工具可能读工作区外的文件）。
  Future<void> notePath(String path) async {
    if (_disposed) return;
    final String? target = resolveInstructionTargetPath(_workdir, _home, path);
    if (target == null || !isWithinWorkdir(target, _workdir)) return;
    final _TargetType type = _typeOf(target);
    String dir = type == _TargetType.directory ? target : parentDir(target);
    while (true) {
      final InstructionDoc? doc = await readInstructionFile(
        joinInstructionPath(dir, 'AGENTS.md'),
        _workdir,
      );
      if (doc != null && _known.add(doc.identity)) {
        _nested.add(doc);
      }
      if (dir == _workdir) return;
      final String parent = parentDir(dir);
      if (parent == dir) return;
      dir = parent;
    }
  }

  /// 释放缓存；之后 [compose] 返回 `null`。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _nested.clear();
    _cached = null;
  }

  Future<String?> _compose() async {
    final List<InstructionDoc> docs = <InstructionDoc>[];
    final Set<String> seen = <String>{};
    for (final String path in globalInstructionPaths(_home, _includeGlobal)) {
      _collect(docs, seen, await readInstructionFile(path, null));
    }
    for (final _ProjectFile file in _projectInstructionFiles(_workdir, _home)) {
      _collect(docs, seen, await readInstructionFile(file.path, file.root));
    }
    for (final InstructionDoc doc in List<InstructionDoc>.of(_nested)) {
      _collect(docs, seen, doc);
    }
    final List<InstructionTarget> targets = resolveInstructionTargets(
      _extra,
      workdir: _workdir,
      home: _home,
    );
    for (final InstructionDoc doc in await loadInstructionTargets(targets)) {
      _collect(docs, seen, doc);
    }
    _cached = _disposed ? null : _joinCapped(docs);
    return _cached;
  }

  void _collect(
    List<InstructionDoc> docs,
    Set<String> seen,
    InstructionDoc? doc,
  ) {
    if (doc == null || !seen.add(doc.identity)) return;
    _known.add(doc.identity);
    docs.add(doc);
  }

  String? _joinCapped(List<InstructionDoc> docs) {
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

  static String? _resolveHome(String? home) {
    final String? value = home ?? defaultInstructionHome();
    if (value == null || value.isEmpty) return null;
    return canonicalDir(value);
  }
}

/// 全局层待读文件：`~/.nava/AGENTS.md` → `~/.config/opencode/AGENTS.md`。
List<String> globalInstructionPaths(String? home, bool enabled) {
  if (!enabled || home == null) return const <String>[];
  final String sep = Platform.pathSeparator;
  return <String>[
    joinInstructionPath(home, '.nava${sep}AGENTS.md'),
    joinInstructionPath(home, '.config${sep}opencode${sep}AGENTS.md'),
  ];
}

/// 项目层待读文件：项目根到工作目录逐层，每层 AGENTS.md / NAVA.md。
List<_ProjectFile> _projectInstructionFiles(String workdir, String? home) {
  final String root = findProjectRoot(workdir, home);
  return <_ProjectFile>[
    for (final String dir in projectChain(root, workdir))
      for (final String name in kInstructionFileNames)
        _ProjectFile(
          joinInstructionPath(dir, name),
          isWithinWorkdir(dir, workdir) ? workdir : root,
        ),
  ];
}

/// 一个项目层待读文件及其越界校验根。
class _ProjectFile {
  const _ProjectFile(this.path, this.root);

  final String path;

  /// canonical 路径必须落在该根内（工作目录内的文件按工作目录校验）。
  final String root;
}

_TargetType _typeOf(String path) =>
    FileSystemEntity.typeSync(path) == FileSystemEntityType.directory
    ? _TargetType.directory
    : _TargetType.file;

/// 目标路径的粗分类。
enum _TargetType { directory, file }
