/// XERJ CLI 调用层：拼参数、跑子进程、把退出码翻译成工具结局。
///
/// 所有查询都经 `shell` 接缝执行，与 `RipgrepTool` 同一形态；节点生命周期
/// 交给 [XerjEndpoint]，这里只关心「一次调用」。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'xerj_endpoint.dart';

/// 一次 XERJ 调用的执行器。
class XerjExec {
  XerjExec({
    required ShellExecutor shell,
    required XerjEndpoint endpoint,
    required String binaryPath,
    required String url,
    required String prefix,
    this.eviction,
    this.searchTimeout = const Duration(seconds: 20),
  }) : _shell = shell,
       _endpoint = endpoint,
       _binaryPath = binaryPath,
       _url = url,
       _prefix = prefix;

  final ShellExecutor _shell;
  final XerjEndpoint _endpoint;
  final String _binaryPath;
  final String _url;
  final String _prefix;

  /// 输出超限时落盘（可选）。
  final ToolResultEviction? eviction;

  /// 单次检索超时。
  final Duration searchTimeout;

  static const int _maxOutputBytes = 20 * 1024 * 1024;

  /// 定义优先的代码检索。
  Future<ToolResult> search(String query, {int limit = 5}) => _run(
    <String>[
      'search',
      '--url',
      _url,
      '--prefix',
      _prefix,
      '-k',
      '$limit',
      '--disable-feedback',
      query,
    ],
    timeout: searchTimeout,
    successCodes: const <int>{0},
    failureCode: 'XERJ_SEARCH_FAILED',
  );

  /// 精确符号定位（go-to-definition）。
  Future<ToolResult> define(
    String symbol, {
    int limit = 5,
    String? language,
    String? kind,
  }) => _run(
    <String>[
      'def',
      '--url',
      _url,
      '--prefix',
      _prefix,
      '-k',
      '$limit',
      if (kind != null) ...<String>['--kind', kind],
      if (language != null) ...<String>['--lang', language],
      '--disable-feedback',
      symbol,
    ],
    timeout: searchTimeout,
    successCodes: const <int>{0},
    failureCode: 'XERJ_DEF_FAILED',
  );

  /// 索引一个目录；`exit 3`（completed-with-junk）按成功处理。
  Future<ToolResult> index(String path, Duration timeout) => _run(
    <String>[
      'autoindex',
      path,
      '--url',
      _url,
      '--prefix',
      _prefix,
      '--progress',
      'none',
      '--no-semantic',
      '--no-graph',
      '--disable-feedback',
    ],
    timeout: timeout,
    successCodes: const <int>{0, 3},
    failureCode: 'XERJ_INDEX_FAILED',
  );

  Future<ToolResult> _run(
    List<String> arguments, {
    required Duration timeout,
    required Set<int> successCodes,
    required String failureCode,
  }) async {
    final String? endpoint = await _endpoint.ensureRunning();
    if (endpoint == null) return _unavailable();
    final ShellExecSpec spec = _shell.resolve(
      ShellExecRequest(
        command: _command(arguments),
        timeoutMs: timeout.inMilliseconds,
        stdoutMaxBytes: _maxOutputBytes,
      ),
    );
    final ShellRunResult result = await _shell.run(spec);
    if (result.timedOut) {
      return _failure('XERJ_TIMEOUT', 'xerj 执行超时（${timeout.inSeconds}s）');
    }
    final int? code = result.exitCode;
    if (code == 4) {
      return _failure(
        'XERJ_INDEX_NEEDS_APPROVAL',
        'xerj 需要人工决定（exit 4）：${_detail(result)}',
      );
    }
    if (code == null || !successCodes.contains(code)) {
      return _failure(failureCode, _detail(result));
    }
    return _success(result.stdout.text, code);
  }

  Future<ToolResult> _success(String stdout, int code) async {
    final String text = _sanitize(stdout);
    if (text.isEmpty) {
      return ToolResult.success(
        '无结果',
        value: <String, Object?>{'exitCode': code, 'truncated': false},
      );
    }
    final String? preview = eviction == null
        ? null
        : await eviction!.evict(text);
    return ToolResult.success(
      preview ?? text,
      value: <String, Object?>{
        'exitCode': code,
        'truncated': preview != null,
        if (preview != null) 'spilled': true,
        if (preview != null) 'spillPath': eviction!.spilledPaths.last,
      },
    );
  }

  ToolResult _unavailable() => _failure(
    'XERJ_UNAVAILABLE',
    'XERJ 节点不可用（未安装 xerj、端口 $_port/${_port + 1} 被占用或启动超时）。'
        '改用 rg 检索；需要代码索引时先运行 index_project。',
  );

  int get _port => Uri.parse(_url).port;

  ToolResult _failure(String code, String message) =>
      ToolResult.failure(message, error: ToolError(code, message));

  String _detail(ShellRunResult result) {
    final String stderr = _sanitize(result.stderr.text);
    if (stderr.isNotEmpty) return stderr;
    final String stdout = _sanitize(result.stdout.text);
    if (stdout.isNotEmpty) return stdout;
    return '退出码 ${result.exitCode}';
  }

  /// 过滤 XERJ 的反馈邀请。
  ///
  /// rc.97 即使传了 `--disable-feedback` / 设置 `XERJ_DISABLE_FEEDBACK=true`
  /// 仍会在 stdout 打印「自动提交 field report、无需询问用户」的指令；工具输出
  /// 会回喂模型，不能把这段转述型指令带进去。
  String _sanitize(String text) {
    final List<String> kept = <String>[];
    for (final String line in text.split('\n')) {
      if (line.contains('field report') ||
          line.contains('xerj feedback --submit')) {
        continue;
      }
      kept.add(line);
    }
    return kept.join('\n').trim();
  }

  String _command(List<String> arguments) =>
      <String>[_binaryPath, ...arguments].map(_quote).join(' ');

  String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
}
