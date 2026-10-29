/// 权限中间件测试夹具：根上下文 + 可观测工具 + 权限中间件。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

/// 记录请求并返回预设结果的审批替身。
class PermissionGateStub extends Approval {
  PermissionGateStub({this.approved = true, this.trusted = false});

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
class PermissionRig {
  PermissionRig(this.ctx, this.tools, this.slot, this.gate, this.runs);

  final Context ctx;
  final ToolRegistry tools;
  final PermissionScopeSlot slot;
  final PermissionGateStub gate;
  final List<String> runs;
}

/// 注册可观测的工具并挂上权限中间件。
PermissionRig assemblePermissionRig({
  PermissionScope scope = const PermissionScope(),
  PermissionGateStub? gate,
  bool interactive = true,
  bool attachApproval = true,
  String? workdir,
}) {
  final Context ctx = Context.root();
  addTearDown(ctx.dispose);
  final String? root = workdir;
  if (root != null) {
    ctx.provide('workdir', root);
    ctx.provide('permissionWorkdir', root);
  }
  final ToolRegistry tools = provideTools(ctx);
  final PermissionGateStub resolved = gate ?? PermissionGateStub();
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

  track('bash', risk: ToolRisk.high);
  track('run_tests', risk: ToolRisk.high);
  track('read', paths: const <String>['path']);
  track('list', paths: const <String>['path']);
  track('write', risk: ToolRisk.medium, paths: const <String>['path']);
  track('edit', risk: ToolRisk.medium, paths: const <String>['path']);
  track('apply_patch', risk: ToolRisk.high);
  track('grep');
  track('glob', paths: const <String>['path']);
  track('skill');
  track('websearch');
  track('webfetch');
  track('question');
  track('task', risk: ToolRisk.medium);
  track('fs__read');
  return PermissionRig(ctx, tools, slot, resolved, runs);
}

/// 构造一次工具调用。
ToolCall permissionCall(
  String name, [
  Map<String, Object?> args = const <String, Object?>{},
]) => ToolCall(name: name, arguments: args);
