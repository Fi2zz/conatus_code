import 'package:conatus_foundation/conatus_foundation.dart';

/// 列出目录内容的工具：按深度展开，目录以 `/` 结尾。
///
/// 走 `'fs'` 接缝，因此与 read_file / glob 受同一套路径约束。
class ListFilesTool extends Tool {
  const ListFilesTool({
    required FileSystem fs,
    this.defaultDepth = 1,
    this.maxDepth = 5,
    this.defaultLimit = 200,
  }) : _fs = fs;

  final FileSystem _fs;

  /// 默认展开深度。
  final int defaultDepth;

  /// 深度硬上限。
  final int maxDepth;

  /// 默认条目数上限。
  final int defaultLimit;

  /// 递归时跳过的目录（按 basename），与 [GlobTool] 保持一致。
  static const Set<String> _skipDirs =
      <String>{'.git', 'node_modules', '.dart_tool', 'build'};

  @override
  String get name => 'list_files';

  @override
  String get description =>
      '列出目录内容（目录以 / 结尾）。递归时跳过 .git / node_modules / .dart_tool / build。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<String> get pathParams => const <String>['path'];

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('path', description: '目录路径，默认当前目录'),
        ParamSpec.integer(
            'depth', description: '展开深度，默认 $defaultDepth，上限 $maxDepth'),
        ParamSpec.integer('limit', description: '条目数上限，默认 $defaultLimit'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final int depth =
        (ctx.optional<int>('depth') ?? defaultDepth).clamp(1, maxDepth);
    final int limit = ctx.optional<int>('limit') ?? defaultLimit;
    final List<String> lines = <String>[];
    try {
      final FsTarget root = await _fs.resolve(ctx.optional<String>('path') ?? '.');
      await _walk(root, depth, limit, '', lines);
    } on FsError catch (e) {
      return ToolResult.failure(e.message, error: ToolError(e.code.code, e.message));
    }
    return ToolResult.success(
      lines.isEmpty ? '（空目录）' : lines.join('\n'),
      value: <String, Object?>{
        'entries': lines,
        'truncated': lines.length >= limit,
      },
    );
  }

  Future<void> _walk(
    FsTarget dir,
    int depth,
    int limit,
    String prefix,
    List<String> out,
  ) async {
    if (depth < 1) return;
    for (final FsDirEntry entry in await _fs.listDir(dir)) {
      if (out.length >= limit) return;
      if (_skipped(entry)) continue;
      final bool isDir = entry.type == FsFileType.directory;
      out.add('$prefix${entry.name}${isDir ? '/' : ''}');
      if (isDir) {
        await _walk(entry.target, depth - 1, limit, '$prefix${entry.name}/', out);
      }
    }
  }

  bool _skipped(FsDirEntry entry) =>
      entry.type == FsFileType.directory && _skipDirs.contains(entry.name);
}
