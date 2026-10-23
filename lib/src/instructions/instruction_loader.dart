/// AGENTS.md 层级加载器：全局 → 项目 → 嵌套 → `instructions`。
///
/// 顺序：`~/.nava/AGENTS.md`、`~/.config/opencode/AGENTS.md`（只读兼容），
/// 项目根到工作目录逐层（每层 `AGENTS.md` 在前、`NAVA.md` 在后），
/// [notePath] 记下的嵌套文件（最近优先），最后是 `instructions` 配置项。
/// 全程按 canonical 路径去重，单文件与总量都有截断上限。
///
/// 安全边界：工作目录内（含嵌套）的文件 canonical 必须仍在工作目录内；项目
/// 祖先层的文件不在 jail 内，允许读取但**禁止符号链接**（`repo/AGENTS.md ->
/// repo/.env` 这种重定向会被跳过）。全局文件与 `instructions` 显式绝对路径
/// 由用户自己指定，不做限制。
library;

import 'dart:io';

import 'instruction_paths.dart';
import 'instruction_project.dart';
import 'instruction_source.dart';

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
  final Set<String> _visitedDirs = <String>{};
  final List<String> _nested = <String>[];
  final Map<String, InstructionDoc?> _urlDocs = <String, InstructionDoc?>{};
  List<InstructionTarget>? _extraTargets;
  String? _cached;
  Future<String?>? _running;
  bool _disposed = false;

  /// 最近一次 [compose] 的结果（供同步 prompt 段读取）。
  String? get current => _disposed ? null : _cached;

  /// 重新装配全部层级；没有可读内容时返回 `null`。
  ///
  /// 并发调用合并到同一趟（prompt 每次 assemble 都会触发一次）；完成后再调用
  /// 即可拿到新结果。URL 内容按会话缓存，重复装配不发网络请求。
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
  /// 返回是否有**新**文件被记入：调用方只在 true 时重新装配，避免每次工具调用
  /// 都重读全部层级。只读不写；目标在 [workdir] 外时直接忽略。
  Future<bool> notePath(String path) async {
    if (_disposed) return false;
    final String? target = resolveInstructionTargetPath(_workdir, _home, path);
    if (target == null || !isWithinWorkdir(target, _workdir)) return false;
    final _TargetType type = _typeOf(target);
    String dir = type == _TargetType.directory ? target : parentDir(target);
    bool noted = false;
    while (true) {
      if (_visitedDirs.add(dir)) {
        final InstructionDoc? doc = await readInstructionFile(
          joinInstructionPath(dir, 'AGENTS.md'),
          _workdir,
        );
        if (doc != null && _known.add(doc.identity)) {
          _nested.add(doc.identity);
          noted = true;
        }
      }
      if (dir == _workdir) return noted;
      final String parent = parentDir(dir);
      if (parent == dir) return noted;
      dir = parent;
    }
  }

  /// 释放缓存；之后 [compose] 返回 `null`。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _nested.clear();
    _urlDocs.clear();
    _cached = null;
  }

  Future<String?> _compose() async {
    final List<InstructionDoc> docs = <InstructionDoc>[];
    final Set<String> seen = <String>{};
    for (final String path in globalInstructionPaths(_home, _includeGlobal)) {
      _collect(docs, seen, await readInstructionFile(path, null));
    }
    for (final ProjectInstructionFile file in projectInstructionFiles(
      _workdir,
      _home,
    )) {
      _collect(
        docs,
        seen,
        await readInstructionFile(file.path, file.root, direct: file.direct),
      );
    }
    for (final String path in List<String>.of(_nested)) {
      _collect(docs, seen, await readInstructionFile(path, _workdir));
    }
    _extraTargets ??= resolveInstructionTargets(
      _extra,
      workdir: _workdir,
      home: _home,
    );
    final List<InstructionDoc> extra = await loadInstructionTargets(
      _extraTargets!,
      cache: _urlDocs,
    );
    for (final InstructionDoc doc in extra) {
      _collect(docs, seen, doc);
    }
    _cached = _disposed ? null : joinInstructionDocs(docs);
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

  static String? _resolveHome(String? home) {
    final String? value = home ?? defaultInstructionHome();
    if (value == null || value.isEmpty) return null;
    return canonicalDir(value);
  }
}

_TargetType _typeOf(String path) =>
    FileSystemEntity.typeSync(path) == FileSystemEntityType.directory
    ? _TargetType.directory
    : _TargetType.file;

/// 目标路径的粗分类。
enum _TargetType { directory, file }
