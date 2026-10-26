/// 声明式自定义工具：CLI（JSON stdin/stdout）与 HTTP（JSON body）后端。
///
/// 工具是用户显式配置的受信端，与 MCP server 同姿态：默认风险 `high`，进审批；
/// CLI 子进程不走 Layer 2 沙箱，HTTP 请求也不受命令沙箱约束。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:http/http.dart' as http;

import '../config/config_schema.dart';
import 'custom_tool_result.dart';

/// 把 `[[tools]]` 注册进当前上下文；返回已注册工具。
List<Tool> provideCustomTools(
  Context ctx, {
  required List<CustomToolConfig> tools,
  required String workdir,
  Credentials? credentials,
  http.Client? httpClient,
}) {
  final List<Tool> registered = <Tool>[];
  for (final CustomToolConfig config in tools) {
    final CustomTool tool = CustomTool(
      config: config,
      workdir: workdir,
      credentials: credentials,
      httpClient: httpClient,
    );
    ctx.effect(() => ctx.tools.register(tool));
    registered.add(tool);
  }
  return registered;
}

/// 一条声明式工具的执行体。
class CustomTool extends Tool {
  CustomTool({
    required this.config,
    required this.workdir,
    this.credentials,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  final CustomToolConfig config;
  final String workdir;
  final Credentials? credentials;
  final http.Client? _httpClient;

  @override
  String get name => config.name;

  @override
  String get description => config.description;

  @override
  ToolRisk get riskLevel => config.risk;

  @override
  Duration get timeout => Duration(milliseconds: config.timeoutMs);

  @override
  List<ParamSpec> get params => config.params;

  @override
  Future<ToolResult> call(ToolContext ctx) {
    return config.isCommand ? _runCommand(ctx) : _runHttp(ctx);
  }

  Future<ToolResult> _runCommand(ToolContext ctx) async {
    final Process process;
    try {
      process = await Process.start(
        _path(config.command!),
        <String>[for (final String arg in config.args) _resolve(arg)],
        workingDirectory: _cwd(),
        environment: _environment(),
      );
    } on ProcessException catch (error) {
      return customToolFailure('无法启动工具 ${config.name}：${error.message}', 'TOOL_START');
    }
    try {
      process.stdin.write(_payload(ctx));
      await process.stdin.close();
    } on Object {
      // 子进程可能不读 stdin 就退出；退出码与 stderr 才是权威结论。
    }
    final Future<String> stdoutText = process.stdout.transform(utf8.decoder).join();
    final Future<String> stderrText = process.stderr.transform(utf8.decoder).join();
    try {
      final int exit = await process.exitCode.timeout(timeout);
      final String out = await stdoutText;
      final String err = await stderrText;
      if (exit != 0) {
        return customToolFailure(
          '工具 ${config.name} 退出码 $exit：${clipCustomToolText(err.trim())}',
          'TOOL_EXIT',
        );
      }
      return parseCustomToolOutput(out);
    } on TimeoutException {
      unawaited(killProcessTree(process.pid));
      stdoutText.ignore();
      stderrText.ignore();
      return customToolFailure(
        '工具 ${config.name} 超时（${config.timeoutMs}ms）',
        'TOOL_TIMEOUT',
      );
    }
  }

  Future<ToolResult> _runHttp(ToolContext ctx) async {
    final http.Client client = _httpClient ?? http.Client();
    try {
      final http.Request request = http.Request(
        config.method,
        Uri.parse(_resolve(config.url!)),
      );
      for (final MapEntry<String, String> header in config.headers.entries) {
        request.headers[header.key] = _resolve(header.value);
      }
      request.headers.putIfAbsent('content-type', () => 'application/json');
      request.body = _payload(ctx);
      final http.StreamedResponse streamed =
          await client.send(request).timeout(timeout);
      final http.Response response =
          await http.Response.fromStream(streamed).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return customToolFailure(
          '工具 ${config.name} HTTP ${response.statusCode}：${clipCustomToolText(response.body)}',
          'TOOL_HTTP',
        );
      }
      return parseCustomToolOutput(response.body);
    } on TimeoutException {
      return customToolFailure('工具 ${config.name} 超时（${config.timeoutMs}ms）', 'TOOL_TIMEOUT');
    } on FormatException catch (error) {
      return customToolFailure('工具 ${config.name} URL 非法：${error.message}', 'TOOL_URL');
    } on Object catch (error) {
      return customToolFailure('工具 ${config.name} 请求失败：$error', 'TOOL_HTTP');
    } finally {
      if (_httpClient == null) client.close();
    }
  }

  String _payload(ToolContext ctx) =>
      jsonEncode(<String, Object?>{'name': config.name, 'arguments': ctx.arguments});

  String _cwd() {
    final String? cwd = config.cwd;
    if (cwd == null) return workdir;
    final String resolved = _path(cwd);
    return resolved.startsWith('/')
        ? resolved
        : '$workdir${Platform.pathSeparator}$resolved';
  }

  Map<String, String> _environment() => <String, String>{
    ...Platform.environment,
    for (final MapEntry<String, String> entry in config.env.entries)
      entry.key: _resolve(entry.value),
  };

  String _path(String value) {
    if (value == '~') return _home;
    if (value.startsWith('~/')) return '$_home/${value.substring(2)}';
    return value;
  }

  String _resolve(String value) => value.replaceAllMapped(
    RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}'),
    (Match match) {
      final String key = match.group(1)!;
      return credentials?.get(key)?.value ?? match.group(0)!;
    },
  );

  String get _home => resolveHomeDir();
}
