/// Hooks：runHooks 执行、Pre 拒绝工具、Post 追加提示、环境变量注入。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  test('runHooks 按序执行并聚合；非零退出标记失败', () async {
    final List<HookResult> results = await runHooks(
      <String>['echo 第一段', 'false', 'echo 第二段'],
      'pre_tool_use',
    );

    expect(results, hasLength(3));
    expect(results[0].ok, isTrue);
    expect(results[0].output, '第一段');
    expect(results[1].ok, isFalse);
    expect(results[2].ok, isTrue);
  });

  test('命令不可用按 127 失败，不抛', () async {
    final List<HookResult> results = await runHooks(
      <String>['/nonexistent/hook-cmd-xyz'],
      'stop',
    );

    expect(results.single.ok, isFalse);
    expect(results.single.exitCode, 127);
  });

  test('环境变量注入 NAVA_HOOK_EVENT/TOOL/ARGS_JSON', () async {
    final Directory dir = Directory.systemTemp.createTempSync('nava-hooks');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String out = '${dir.path}${Platform.pathSeparator}out.txt';
    final Hooks hooks = Hooks(config: HooksConfig(preToolUse: <String>[
      'printf "%s|%s|%s" "\$NAVA_HOOK_EVENT" "\$NAVA_HOOK_TOOL" '
          '"\$NAVA_HOOK_ARGS_JSON" > $out',
    ]));

    final String? denial = await hooks.preToolUse(
      const ToolCall(name: 'git_status', arguments: <String, Object?>{'a': 1}),
    );

    expect(denial, isNull);
    expect(
      File(out).readAsStringSync(),
      contains('pre_tool_use|git_status|{"a":1}'),
    );
  });

  test('Pre 非零退出拒绝工具；Post 失败追加提示', () async {
    final Context app = Context.root();
    provideTools(app);
    final Hooks hooks = Hooks(config: const HooksConfig(
      preToolUse: <String>['false'],
      postToolUse: <String>['false'],
    ));
    hooks.mount(app.tools);
    app.effect(() => app.tools.fn(
          'echo_tool',
          description: '回显',
          params: <ParamSpec>[ParamSpec.string('text', required: true)],
          handler: (ToolContext ctx) async =>
              ToolResult.success(ctx.str('text')),
        ));
    addTearDown(app.dispose);

    // Pre 拒绝。
    final ToolResult denied = await app.tools.call(const ToolCall(
      name: 'echo_tool',
      arguments: <String, Object?>{'text': 'hi'},
    ));
    expect(denied.isError, isTrue);
    expect(denied.error?.code, 'HOOK_REJECTED');
    expect(denied.content, contains('PreToolUse hook 拒绝'));

    // 只留 Post：工具照常执行，结果追加提示。
    final Context postApp = Context.root();
    provideTools(postApp);
    final Hooks postHooks = Hooks(config: const HooksConfig(postToolUse: <String>['false']));
    postHooks.mount(postApp.tools);
    postApp.effect(() => postApp.tools.fn(
          'echo_tool',
          description: '回显',
          params: <ParamSpec>[ParamSpec.string('text', required: true)],
          handler: (ToolContext ctx) async =>
              ToolResult.success(ctx.str('text')),
        ));
    addTearDown(postApp.dispose);

    final ToolResult ran = await postApp.tools.call(const ToolCall(
      name: 'echo_tool',
      arguments: <String, Object?>{'text': '正文'},
    ));
    expect(ran.isError, isFalse);
    expect(ran.content, contains('正文'));
    expect(ran.content, contains('[PostToolUse]'));
  });

  test('工具失败时 post hook 提示附加但失败语义保留', () async {
    final Context app = Context.root();
    provideTools(app);
    final Hooks hooks = Hooks(config: const HooksConfig(
      postToolUse: <String>['false'],
    ));
    hooks.mount(app.tools);
    app.effect(() => app.tools.fn(
          'fail_tool',
          description: '失败',
          params: <ParamSpec>[],
          handler: (ToolContext ctx) async => ToolResult.failure(
            '失败正文',
            error: const ToolError('BOOM', 'tool exploded'),
          ),
        ));
    addTearDown(app.dispose);

    final ToolResult result =
        await app.tools.call(const ToolCall(name: 'fail_tool'));
    expect(result.isError, isTrue);
    expect(result.error?.code, 'BOOM');
    expect(result.content, contains('失败正文'));
    expect(result.content, contains('[PostToolUse]'));
  });

  test('onStop 失败返回提示；无配置返回 null', () async {
    final Hooks none = Hooks(config: const HooksConfig());
    expect(await none.onStop(), isNull);

    final Hooks failing =
        Hooks(config: const HooksConfig(stop: <String>['false']));
    expect(await failing.onStop(), isNotNull);
  });
}
