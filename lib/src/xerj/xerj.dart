/// XERJ 代码检索的装配入口。
///
/// 仿 `provideFsTools` 的形态：注册三个工具，撤销随上下文生命周期。XERJ
/// 是可选外部二进制——找不到 `xerj` 或拿不到数据目录时不注册任何工具，
/// 调用方的行为与接入前完全一致。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'xerj_binary.dart';
import 'xerj_endpoint.dart';
import 'xerj_exec.dart';
import 'xerj_node.dart';
import 'xerj_tools.dart';

/// XERJ 接入选项。`workdir` 决定索引前缀的自动派生。
class XerjOptions {
  const XerjOptions({
    required this.workdir,
    this.url = 'http://127.0.0.1:19200',
    this.dataDir,
    this.prefix,
    this.indexPrefix = 'nava',
    this.binary,
    this.endpoint,
    this.startTimeout = const Duration(seconds: 8),
    this.searchTimeout = const Duration(seconds: 20),
    this.indexTimeout = const Duration(minutes: 10),
    this.defaultLimit = 5,
  });

  /// 当前项目目录（索引范围与 `index_project` 的默认路径）。
  final String workdir;

  /// ES 兼容端点；非默认端口以避开本机 Elasticsearch。
  final String url;

  /// 节点数据目录；必须位于被索引的工作区之外。为空且未注入 [endpoint] 时不启用。
  final String? dataDir;

  /// 显式索引前缀；为空时按 [indexPrefix] + 工作区哈希派生。
  final String? prefix;

  /// 自动前缀的品牌部分（nava / cowriter）。
  final String indexPrefix;

  /// 可执行文件；为空时从 PATH 探测。
  final XerjBinary? binary;

  /// 节点端点注入点（测试或外部托管节点）。
  final XerjEndpoint? endpoint;

  /// 启动等待上限。
  final Duration startTimeout;

  /// 单次检索超时。
  final Duration searchTimeout;

  /// `index_project` 的超时。
  final Duration indexTimeout;

  /// 检索默认条数。
  final int defaultLimit;

  /// 实际使用的索引前缀：显式优先，否则 `<品牌>-<工作区哈希>`。
  ///
  /// 按工作区隔离，避免同一节点上多个项目的索引互相污染。
  String get resolvedPrefix => prefix ?? '$indexPrefix-${_pathHash(workdir)}';

  static String _pathHash(String path) {
    var hash = 0x811c9dc5;
    for (final int unit in path.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

/// 注册 XERJ 检索工具；不可用时返回空列表。
///
/// 依赖 `'shell'` 子进程接缝（缺省从上下文取）。节点由本函数创建时，其
/// 释放挂在上下文上；注入 [XerjOptions.endpoint] 时由调用方负责生命周期。
List<Tool> provideXerjSearch(
  Context ctx, {
  required XerjOptions options,
  ShellExecutor? shell,
  ToolResultEviction? eviction,
}) {
  final ShellExecutor? executor = shell ?? ctx.get<ShellExecutor>('shell');
  final XerjBinary? binary = options.binary ?? XerjBinary.discover();
  final XerjEndpoint? endpoint =
      options.endpoint ?? _node(ctx, options, binary);
  if (executor == null || endpoint == null) return const <Tool>[];

  final XerjExec exec = XerjExec(
    shell: executor,
    endpoint: endpoint,
    binaryPath: binary?.path ?? 'xerj',
    url: options.url,
    prefix: options.resolvedPrefix,
    eviction: eviction,
    searchTimeout: options.searchTimeout,
  );
  final List<Tool> tools = <Tool>[
    CodeSearchTool(exec, defaultLimit: options.defaultLimit),
    FindDefinitionTool(exec, defaultLimit: options.defaultLimit),
    IndexProjectTool(
      exec,
      workdir: options.workdir,
      timeout: options.indexTimeout,
    ),
  ];
  for (final Tool tool in tools) {
    ctx.effect(() => ctx.tools.register(tool));
  }
  return tools;
}

XerjEndpoint? _node(Context ctx, XerjOptions options, XerjBinary? binary) {
  final String? dataDir = options.dataDir;
  if (binary == null || dataDir == null) return null;
  final XerjNode node = XerjNode(
    binary: binary,
    dataDir: dataDir,
    url: options.url,
    startTimeout: options.startTimeout,
  );
  ctx.onDispose(node.dispose);
  return node;
}
