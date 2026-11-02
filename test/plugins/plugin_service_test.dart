/// 插件工具与 shell 环境装饰器。
library;

import 'dart:io';

import 'package:conatus_code/src/plugins/plugin_entry.dart';
import 'package:conatus_code/src/plugins/plugin_env_shell.dart';
import 'package:conatus_code/src/plugins/plugin_service.dart';
import 'package:conatus_code/src/plugins/plugin_tool.dart';
import 'package:conatus_code/src/plugins/plugin_types.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  test('PluginTool 保留插件给的 JSON Schema', () async {
    final PluginTool tool = PluginTool(
      name: 'plugin_echo',
      description: 'echo',
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'text': <String, Object?>{'type': 'string'},
        },
        'required': <String>['text'],
      },
      execute: (Map<String, Object?> args, String callId) async =>
          'echo:${args['text']}',
    );
    expect(tool.toSchema()['parameters'], tool.parameters);
    final ToolResult result = await tool.call(
      const ToolContext(
        ToolCall(
          name: 'plugin_echo',
          arguments: <String, Object?>{'text': 'hi'},
        ),
      ),
    );
    expect(result.isError, isFalse);
    expect(result.content, 'echo:hi');
  });

  test('PluginTool 异常收敛为失败结果', () async {
    final PluginTool tool = PluginTool(
      name: 'boom',
      description: 'boom',
      parameters: const <String, Object?>{},
      execute: (Map<String, Object?> args, String callId) async =>
          throw StateError('boom'),
    );
    final ToolResult result = await tool.call(
      const ToolContext(ToolCall(name: 'boom')),
    );
    expect(result.isError, isTrue);
    expect(result.error?.code, 'PLUGIN_TOOL_ERROR');
  });

  test('无 node 时返回 no-op 并提示', () async {
    final List<String> warnings = <String>[];
    final PluginService service = await PluginService.start(
      candidates: <PluginCandidate>[
        localPluginCandidate(
          '${Directory.current.path}/test/plugins/fixtures/v1_plugin.js',
        ),
      ],
      workdir: Directory.current.path,
      homeDir: Directory.current.path,
      tools: ToolRegistry(),
      warn: warnings.add,
      nodeResolver: () async => null,
    );
    expect(service.available, isFalse);
    expect(warnings.join(), contains('node'));
    await service.close();
  });

  test('PluginEnvShell 合并插件环境变量', () {
    final _FakeShell inner = _FakeShell();
    final PluginEnvShell shell = PluginEnvShell(
      inner: inner,
      env: <String, String>{'PLUGIN_ENV': '1'},
    );
    final ShellExecSpec spec = shell.resolve(
      const ShellExecRequest(
        command: 'echo hi',
        env: <String, String>{'BASE': '1'},
      ),
    );
    expect(spec.env, <String, String>{'BASE': '1', 'PLUGIN_ENV': '1'});
  });
}

class _FakeShell implements ShellExecutor {
  @override
  ShellExecSpec resolve(ShellExecRequest request) => ShellExecSpec(
    command: request.command,
    workdir: '/tmp',
    timeoutMs: 1000,
    stdoutMaxBytes: 1000,
    env: request.env,
  );

  @override
  Future<ShellRunResult> run(ShellExecSpec spec) async => const ShellRunResult(
    exitCode: 0,
    timedOut: false,
    timeoutMs: 1000,
    stdout: CollectedOutput(text: ''),
    stderr: CollectedOutput(text: ''),
  );

  @override
  Future<ShellProcess> start(ShellExecSpec spec) => throw UnimplementedError();
}
