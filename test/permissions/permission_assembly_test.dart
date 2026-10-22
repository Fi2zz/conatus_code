/// 权限中间件装配：动作映射、拒绝 / 询问 / 放行与零配置兼容。
library;

import 'dart:io';

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
  String? workdir,
}) {
  final Context ctx = Context.root();
  addTearDown(ctx.dispose);
  if (workdir != null) ctx.provide('workdir', workdir);
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
  track('list_files', paths: const <String>['path']);
  track('write_file', risk: ToolRisk.medium, paths: const <String>['path']);
  track('edit_file', risk: ToolRisk.medium, paths: const <String>['path']);
  track('apply_patch', risk: ToolRisk.high);
  track('rg');
  track('glob', paths: const <String>['path']);
  track('skill');
  track('web_search');
  track('spawn_agent', risk: ToolRisk.medium);
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
              action: 'read',
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

    test('read_file / list_files 映射为 read', () async {
      final ApprovalRequest read = await askFor(
        'read_file',
        'read',
        <String, Object?>{'path': 'src/a.dart'},
      );
      expect(read.action, 'read');
      expect(read.resources, <String>['src/a.dart']);
      final ApprovalRequest list = await askFor(
        'list_files',
        'read',
        <String, Object?>{'path': 'src'},
      );
      expect(list.action, 'read');
    });

    test('write_file / edit_file / apply_patch 映射为 edit', () async {
      final ApprovalRequest write = await askFor(
        'write_file',
        'edit',
        <String, Object?>{'path': 'a.txt'},
      );
      expect(write.action, 'edit');
      final ApprovalRequest edit = await askFor(
        'edit_file',
        'edit',
        <String, Object?>{'path': 'a.txt'},
      );
      expect(edit.action, 'edit');
      final ApprovalRequest patch =
          await askFor('apply_patch', 'edit', <String, Object?>{'patch': '--- a'});
      expect(patch.action, 'edit');
    });

    test('rg 映射为 grep', () async {
      final ApprovalRequest request = await askFor(
        'rg',
        'grep',
        <String, Object?>{'pattern': 'TODO'},
      );
      expect(request.action, 'grep');
    });

    test('spawn_agent 映射为 subagent，资源缺省 default', () async {
      final ApprovalRequest request = await askFor(
        'spawn_agent',
        'subagent',
        <String, Object?>{'task': '查一下'},
      );
      expect(request.action, 'subagent');
      expect(request.resources, <String>['default']);
    });
  });

  group('动作规则', () {
    test('action=edit + resource=* 拦截三种写工具', () async {
      final _Rig rig = _assemble(
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'edit',
              resource: '*',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );

      for (final String tool in <String>[
        'write_file',
        'edit_file',
        'apply_patch',
      ]) {
        final ToolResult result = await rig.tools.call(
          _call(tool, <String, Object?>{'path': 'a.txt', 'patch': '--- a'}),
        );
        expect(result.error!.code, 'PERMISSION_DENIED', reason: tool);
      }
      expect(rig.runs, isEmpty);
    });

    test('action=read 覆盖 read_file / list_files', () async {
      final _Rig rig = _assemble(
        scope: const PermissionScope(
          askThreshold: ToolRisk.high,
          rules: <PermissionRule>[
            PermissionRule(
              action: 'read',
              resource: '*',
              effect: PermissionEffect.allow,
            ),
          ],
        ),
      );

      await rig.tools.call(
        _call('read_file', <String, Object?>{'path': '/tmp/a.txt'}),
      );
      await rig.tools.call(
        _call('list_files', <String, Object?>{'path': '/tmp'}),
      );
      expect(rig.gate.requests, isEmpty);
      expect(rig.runs, <String>['read_file', 'list_files']);
    });

    test('action=grep 命中 rg，action=shell 命中 run_command', () async {
      final _Rig grepRig = _assemble(
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'grep',
              resource: '*',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );
      final ToolResult grep = await grepRig.tools.call(
        _call('rg', <String, Object?>{'pattern': 'TODO'}),
      );
      expect(grep.error!.code, 'PERMISSION_DENIED');

      final _Rig shellRig = _assemble(
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'shell',
              resource: '*',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );
      final ToolResult shell = await shellRig.tools.call(
        _call('run_command', <String, Object?>{'command': 'echo hi'}),
      );
      expect(shell.error!.code, 'PERMISSION_DENIED');
    });

    test('action=edit + resource=*.env 只拦截补丁里的 .env 目标', () async {
      final _Rig rig = _assemble(
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'edit',
              resource: '*.env',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );

      final ToolResult blocked = await rig.tools.call(
        _call('apply_patch', <String, Object?>{
          'patch': '*** Update File: config/.env\n@@ -1 +1 @@\n-A=1\n+A=2',
        }),
      );
      expect(blocked.error!.code, 'PERMISSION_DENIED');
      expect(rig.runs, isEmpty);

      final ToolResult allowed = await rig.tools.call(
        _call('apply_patch', <String, Object?>{
          'patch': '*** Update File: src/a.dart\n@@ -1 +1 @@\n-a\n+b',
        }),
      );
      expect(allowed.isError, isFalse);
      expect(rig.runs, <String>['apply_patch']);
    });

    test('apply_patch 解析 Add / Delete / Move to 且去重', () async {
      final _Rig rig = _assemble(
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'edit',
              resource: 'secret/*',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );

      final ToolResult deleted = await rig.tools.call(
        _call('apply_patch', <String, Object?>{
          'patch': '*** Delete File: secret/key.txt',
        }),
      );
      expect(deleted.error!.code, 'PERMISSION_DENIED');

      final ToolResult moved = await rig.tools.call(
        _call('apply_patch', <String, Object?>{
          'patch': '*** Update File: src/a.dart\n'
              '*** Move to: secret/b.dart\n',
        }),
      );
      expect(moved.error!.code, 'PERMISSION_DENIED');
    });

    test('action=glob + resource=**/*.dart 命中 glob pattern', () async {
      final _Rig rig = _assemble(
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'glob',
              resource: '**/*.dart',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );

      final ToolResult result = await rig.tools.call(
        _call('glob', <String, Object?>{
          'pattern': '**/*.dart',
          'path': 'src',
        }),
      );
      expect(result.error!.code, 'PERMISSION_DENIED');
      expect(rig.runs, isEmpty);
    });

    test('action=skill + resource=review 命中技能名', () async {
      final _Rig rig = _assemble(
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'skill',
              resource: 'review',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );

      final ToolResult result = await rig.tools.call(
        _call('skill', <String, Object?>{'name': 'review'}),
      );
      expect(result.error!.code, 'PERMISSION_DENIED');
      expect(rig.runs, isEmpty);
    });
  });

  group('external_directory', () {
    test('工作区外 read 进入 external_directory 判定并要求确认', () async {
      final Directory work = Directory.systemTemp.createTempSync('perm-work');
      final Directory outside =
          Directory.systemTemp.createTempSync('perm-outside');
      addTearDown(() => work.deleteSync(recursive: true));
      addTearDown(() => outside.deleteSync(recursive: true));
      final String file = '${outside.path}${Platform.pathSeparator}a.txt';
      final _Rig rig = _assemble(
        workdir: work.path,
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'external_directory',
              resource: '*',
              effect: PermissionEffect.ask,
            ),
          ],
        ),
      );

      final ToolResult result =
          await rig.tools.call(_call('read_file', <String, Object?>{'path': file}));
      expect(result.isError, isFalse);
      final ApprovalRequest request = rig.gate.requests.single;
      expect(request.action, 'external_directory');
      expect(request.resources.single, endsWith('/*'));
    });

    test('工作区内 read 不触发 external_directory', () async {
      final Directory work = Directory.systemTemp.createTempSync('perm-work');
      addTearDown(() => work.deleteSync(recursive: true));
      final String file = '${work.path}${Platform.pathSeparator}a.txt';
      final _Rig rig = _assemble(
        workdir: work.path,
        scope: const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'external_directory',
              resource: '*',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      );

      await rig.tools.call(
        _call('read_file', <String, Object?>{'path': file}),
      );
      expect(rig.runs, <String>['read_file']);
    });
  });
}
