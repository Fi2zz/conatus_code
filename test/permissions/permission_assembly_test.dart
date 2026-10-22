/// 权限中间件装配：动作映射、拒绝 / 询问 / 放行与零配置兼容。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

/// 记录请求并返回预设结果的审批替身。
class _Gate extends Approval {
  _Gate({this.approved = true, this.trusted = false});

  bool approved;
  bool trusted;
  final List<ApprovalRequest> requests = <ApprovalRequest>[];

  @override
  Stream<ApprovalRequest> get pending => const Stream<ApprovalRequest>.empty();

  @override
  Future<bool> preapproved(ApprovalRequest request) async => trusted;

  @override
  Future<bool> request(ApprovalRequest request) async {
    requests.add(request);
    return approved;
  }
}

/// 一套装配好的根上下文与工具表。
class _Rig {
  _Rig(this.ctx, this.tools, this.slot, this.gate, this.runs);

  final Context ctx;
  final ToolRegistry tools;
  final PermissionScopeSlot slot;
  final _Gate gate;
  final List<String> runs;
}

/// 注册可观测的工具并挂上权限中间件。
_Rig _assemble({
  PermissionScope scope = const PermissionScope(),
  _Gate? gate,
  bool interactive = true,
  bool attachApproval = true,
}) {
  final Context ctx = Context.root();
  addTearDown(ctx.dispose);
  final ToolRegistry tools = provideTools(ctx);
  final _Gate resolved = gate ?? _Gate();
  if (attachApproval) {
    provideApproval(ctx, approval: resolved, instrument: false);
  }
  final PermissionScopeSlot slot = PermissionScopeSlot(scope);
  ctx.provide(kPermissionScopeService, slot);
  instrumentPermission(ctx, interactive: interactive);
  final List<String> runs = <String>[];
  void track(
    String name, {
    ToolRisk risk = ToolRisk.low,
    List<String> paths = const <String>[],
  }) {
    tools.fn(
      name,
      riskLevel: risk,
      pathParams: paths,
      handler: (ToolContext c) async {
        runs.add(name);
        return ToolResult.success(name);
      },
    );
  }

  track('run_command', risk: ToolRisk.high);
  track('run_tests', risk: ToolRisk.high);
  track('read_file', paths: const <String>['path']);
  track('web_search');
  track('fs__read_file');
  return _Rig(ctx, tools, slot, resolved, runs);
}

ToolCall _call(
  String name, [
  Map<String, Object?> args = const <String, Object?>{},
]) => ToolCall(name: name, arguments: args);

void main() {
  group('显式 deny', () {
    test('never_ask（阈值 null）下仍然拒绝，执行体不运行', () async {
      final _Rig rig = _assemble(
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'shell',
              resource: 'git push *',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );

      final ToolResult result = await rig.tools.call(
        _call('run_command', <String, Object?>{
          'command': 'git push origin main',
        }),
      );

      expect(result.isError, isTrue);
      expect(result.error!.code, 'PERMISSION_DENIED');
      expect(rig.runs, isEmpty);
    });

    test('headless 下显式 deny 依旧生效', () async {
      final _Rig rig = _assemble(
        interactive: false,
        attachApproval: false,
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'shell',
              resource: 'rm *',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );

      final ToolResult result = await rig.tools.call(
        _call('run_command', <String, Object?>{'command': 'rm -rf x'}),
      );
      expect(result.error!.code, 'PERMISSION_DENIED');
      expect(rig.runs, isEmpty);
    });
  });

  group('零配置兼容', () {
    test('高危工具按阈值询问，批准后执行', () async {
      final _Rig rig = _assemble(
        scope: const PermissionScope(askThreshold: ToolRisk.high),
      );

      final ToolResult result = await rig.tools.call(
        _call('run_command', <String, Object?>{'command': 'ls'}),
      );

      expect(result.isError, isFalse);
      expect(rig.gate.requests, hasLength(1));
      expect(rig.gate.requests.single.toolName, 'run_command');
      expect(rig.gate.requests.single.action, 'shell');
      expect(rig.runs, <String>['run_command']);
    });

    test('拒绝时返回 APPROVAL_DENIED 且不执行', () async {
      final _Rig rig = _assemble(
        scope: const PermissionScope(askThreshold: ToolRisk.high),
        gate: _Gate(approved: false),
      );

      final ToolResult result = await rig.tools.call(
        _call('run_command', <String, Object?>{'command': 'ls'}),
      );
      expect(result.error!.code, 'APPROVAL_DENIED');
      expect(rig.runs, isEmpty);
    });

    test('声明路径参数的低风险工具仍会询问（目录信任的前提）', () async {
      final _Rig rig = _assemble(
        scope: const PermissionScope(askThreshold: ToolRisk.high),
      );

      final ToolResult result = await rig.tools.call(
        _call('read_file', <String, Object?>{'path': '/tmp/a.txt'}),
      );
      expect(result.isError, isFalse);
      expect(rig.gate.requests, hasLength(1));
      expect(rig.gate.requests.single.pathArgs, <String>['/tmp/a.txt']);
      expect(rig.gate.requests.single.resources, <String>['/tmp/a.txt']);
    });

    test('preapproved 覆盖路径时直接放行，不打扰用户', () async {
      final _Rig rig = _assemble(
        scope: const PermissionScope(askThreshold: ToolRisk.high),
        gate: _Gate(trusted: true),
      );

      await rig.tools.call(
        _call('read_file', <String, Object?>{'path': '/tmp/a.txt'}),
      );
      expect(rig.gate.requests, isEmpty);
      expect(rig.runs, <String>['read_file']);
    });

    test('never_ask 下路径工具不询问，直接放行', () async {
      final _Rig rig = _assemble();

      await rig.tools.call(
        _call('read_file', <String, Object?>{'path': '/tmp/a.txt'}),
      );
      expect(rig.gate.requests, isEmpty);
      expect(rig.runs, <String>['read_file']);
    });

    test('显式 allow 规则跳过路径询问', () async {
      final _Rig rig = _assemble(
        scope: const PermissionScope(
          askThreshold: ToolRisk.high,
          rules: <PermissionRule>[
            PermissionRule(
              action: 'read_file',
              resource: '*',
              effect: PermissionEffect.allow,
            ),
          ],
        ),
      );

      await rig.tools.call(
        _call('read_file', <String, Object?>{'path': '/tmp/a.txt'}),
      );
      expect(rig.gate.requests, isEmpty);
      expect(rig.runs, <String>['read_file']);
    });
  });

  group('headless', () {
    test('需要询问时拒绝并返回 PERMISSION_ASK_UNATTENDED', () async {
      final _Rig rig = _assemble(
        interactive: false,
        attachApproval: false,
        scope: const PermissionScope(askThreshold: ToolRisk.high),
      );

      final ToolResult result = await rig.tools.call(
        _call('run_command', <String, Object?>{'command': 'ls'}),
      );
      expect(result.error!.code, 'PERMISSION_ASK_UNATTENDED');
      expect(rig.runs, isEmpty);
    });

    test('零配置下路径工具不触发目录询问（旧行为不拦）', () async {
      final _Rig rig = _assemble(
        interactive: false,
        attachApproval: false,
        scope: const PermissionScope(askThreshold: ToolRisk.high),
      );

      final ToolResult result = await rig.tools.call(
        _call('read_file', <String, Object?>{'path': '/tmp/a.txt'}),
      );
      expect(result.isError, isFalse);
      expect(rig.runs, <String>['read_file']);
    });

    test('显式 allow / never_ask 仍可放行', () async {
      final _Rig rig = _assemble(
        interactive: false,
        attachApproval: false,
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'shell',
              resource: 'ls *',
              effect: PermissionEffect.allow,
            ),
          ],
        ),
      );

      await rig.tools.call(
        _call('run_command', <String, Object?>{'command': 'ls -la'}),
      );
      expect(rig.runs, <String>['run_command']);
    });
  });

  group('动作映射', () {
    Future<ApprovalRequest> askFor(
      String tool,
      String action,
      Map<String, Object?> args,
    ) async {
      final _Rig rig = _assemble(
        scope: PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: action,
              resource: '*',
              effect: PermissionEffect.ask,
            ),
          ],
        ),
      );
      await rig.tools.call(_call(tool, args));
      return rig.gate.requests.single;
    }

    test('run_tests 映射为 shell', () async {
      final ApprovalRequest request = await askFor(
        'run_tests',
        'shell',
        <String, Object?>{'test_cmd': 'dart test'},
      );
      expect(request.action, 'shell');
      expect(request.resources, <String>['dart test']);
    });

    test('web_search 映射为 websearch，资源为查询词', () async {
      final ApprovalRequest request = await askFor(
        'web_search',
        'websearch',
        <String, Object?>{'query': 'dart'},
      );
      expect(request.action, 'websearch');
      expect(request.resources, <String>['dart']);
    });

    test('MCP server__tool 映射为 server_tool', () async {
      final ApprovalRequest request = await askFor(
        'fs__read_file',
        'fs_read_file',
        <String, Object?>{},
      );
      expect(request.action, 'fs_read_file');
      expect(request.resources, <String>['*']);
    });
  });
}
