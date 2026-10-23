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
import '../read_only_paths.dart';

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
    this.env,
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

  /// 解析令牌目录用的环境变量；缺省 [Platform.environment]（测试注入用）。
  final Map<String, String>? env;
}

typedef _AddRequest = ({
  String name,
  String? url,
  List<String>? command,
  bool? oauth,
});

typedef _Invocation = ({List<String> args, String? configPath, String? error});

const String _usage = '''
用法：nava mcp <子命令> [--config <路径>]
  add <名字> --url <地址>       添加远程 server（http）
  add <名字> --no-oauth --url <地址>  添加远程 server 并关闭 OAuth
  add <名字> -- <命令...>       添加 stdio server
  list                         列出已配置的 server（不连接）
  auth <名字>                  对远程 server 做 OAuth 登录并保存令牌
  logout <名字>                删除该 server 的 OAuth 令牌
  --oauth / --no-oauth         远程 server 的 OAuth 开关（缺省启用）
  --global                     写全局配置（当前只有全局配置，等同缺省）
  --config <路径>              配置文件路径（缺省 ~/.nava/config.toml，
                               也可用 NAVA_HOME 指定配置目录）''';

/// 执行 `nava mcp` 子命令，返回进程退出码。
Future<int> runMcpCli(
  List<String> args, {
  String? configPath,
  McpCliDeps deps = const McpCliDeps(),
}) async {
  final _Invocation invocation = _extractConfig(args, configPath);
  if (invocation.error != null) return _usageError(deps, invocation.error!);
  final List<String> rest = invocation.args;
  if (rest.isEmpty) return _usageError(deps, '缺少子命令。');
  final String action = rest.first;
  if (action == 'help' || action == '--help' || action == '-h') {
    _out(deps).writeln(_usage);
    return 0;
  }
  final List<String> subArgs = rest.sublist(1);
  switch (action) {
    case 'add':
      return _add(subArgs, invocation.configPath, deps);
    case 'list':
      return _list(subArgs, invocation.configPath, deps);
    case 'auth':
      return _auth(subArgs, invocation.configPath, deps);
    case 'logout':
      return _logout(subArgs, deps);
    default:
      return _usageError(deps, '未知子命令 mcp $action。');
  }
}

/// 提取全局 `--config <路径>`；`--` 之后的参数原样交给 stdio 命令。
_Invocation _extractConfig(List<String> args, String? fallback) {
  final List<String> kept = <String>[];
  String? path = fallback;
  for (int index = 0; index < args.length; index++) {
    final String arg = args[index];
    if (arg == '--') {
      kept.addAll(args.sublist(index));
      break;
    }
    if (arg != '--config') {
      kept.add(arg);
      continue;
    }
    if (index + 1 >= args.length) {
      return (
        args: const <String>[],
        configPath: path,
        error: '--config 缺少路径。',
      );
    }
    path = args[++index];
  }
  return (args: kept, configPath: path, error: null);
}

int _usageError(McpCliDeps deps, String message) {
  _err(deps).writeln('用法错误：$message\n$_usage');
  return 2;
}

StringSink _out(McpCliDeps deps) => deps.out ?? stdout;

StringSink _err(McpCliDeps deps) => deps.err ?? stderr;
