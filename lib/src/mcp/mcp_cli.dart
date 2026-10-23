/// `nava mcp` 子命令：add / list / auth / logout。
///
/// 只写 `~/.nava/config.toml` 与 `~/.nava/oauth/`；`.opencode` 与
/// `~/.config/opencode` 是只读兼容目录，显式拒绝写入。成功 0，用法 / 运行
/// 错误 2。`list` 只读配置，不连接任何 server。
library;

import 'dart:io';

import 'package:conatus_mcp/conatus_mcp.dart';

import '../config/config_atomic_write.dart';
import '../config/config_loader.dart';
import '../config/config_mcp_writer.dart';
import '../config/config_parser.dart';
import '../config/config_path.dart';
import '../config/config_schema.dart';

part 'mcp_cli_add.dart';
part 'mcp_cli_auth.dart';
part 'mcp_cli_list.dart';

/// CLI 的可注入依赖：测试用内存输出、假会话与临时令牌目录。
class McpCliDeps {
  /// 全部可选；缺省写标准输出 / 错误流、真实 OAuth 会话与 `~/.nava/oauth`。
  const McpCliDeps({
    this.out,
    this.err,
    this.session,
    this.oauthStore,
    this.openUrl,
  });

  /// 正常输出目标。
  final StringSink? out;

  /// 错误输出目标。
  final StringSink? err;

  /// 注入的 OAuth 会话；为 `null` 时按需创建并负责关闭。
  final McpOAuthSession? session;

  /// 注入的令牌存储；为 `null` 时用 `resolveOAuthTokenDir()`。
  final McpOAuthStore? oauthStore;

  /// 打开授权 URL 的回调；测试用它模拟浏览器点击。
  final void Function(Uri)? openUrl;
}

typedef _AddRequest = ({
  String name,
  String? url,
  List<String>? command,
  bool? oauth,
});

const String _usage = '''
用法：nava mcp <子命令>
  add <名字> --url <地址>       添加远程 server（http）
  add <名字> --no-oauth --url <地址>  添加远程 server 并关闭 OAuth
  add <名字> -- <命令...>       添加 stdio server
  list                         列出已配置的 server（不连接）
  auth <名字>                  对远程 server 做 OAuth 登录并保存令牌
  logout <名字>                删除该 server 的 OAuth 令牌
  --global                     写全局配置（当前只有全局配置）''';

/// 执行 `nava mcp` 子命令，返回进程退出码。
Future<int> runMcpCli(
  List<String> args, {
  String? configPath,
  McpCliDeps deps = const McpCliDeps(),
}) async {
  if (args.isEmpty) return _usageError(deps, '缺少子命令。');
  final String action = args.first;
  if (action == 'help' || action == '--help' || action == '-h') {
    _out(deps).writeln(_usage);
    return 0;
  }
  final List<String> rest = args.sublist(1);
  switch (action) {
    case 'add':
      return _add(rest, configPath, deps);
    case 'list':
      return _list(rest, configPath, deps);
    case 'auth':
      return _auth(rest, configPath, deps);
    case 'logout':
      return _logout(rest, deps);
    default:
      return _usageError(deps, '未知子命令 mcp $action。');
  }
}

/// `.opencode` / `~/.config/opencode` 只读：任何写入路径都拒绝。
bool _protectedPath(String path) {
  final String normalized = path.replaceAll(r'\', '/');
  return normalized.contains('/.opencode/') ||
      normalized.endsWith('/.opencode') ||
      normalized.contains('/.config/opencode/') ||
      normalized.endsWith('/.config/opencode');
}

int _usageError(McpCliDeps deps, String message) {
  _err(deps).writeln('用法错误：$message\n$_usage');
  return 2;
}

StringSink _out(McpCliDeps deps) => deps.out ?? stdout;

StringSink _err(McpCliDeps deps) => deps.err ?? stderr;
