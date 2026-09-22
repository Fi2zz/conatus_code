/// update_plan 工具：执行中推进 / 修订当前会话的执行计划。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

/// `update_plan` 工具：按步骤序号更新当前计划。
///
/// 序号与计划面板 / system prompt 里的「1. [ ] text」一致；不带 `index` 的
/// 条目追加到末尾。更新写回 `plan/updated` 事件，面板与后续摘要即时反映。
class UpdatePlanTool extends Tool {
  UpdatePlanTool({required this.session});

  /// 计划持久化到的会话。
  final Session session;

  @override
  String get name => 'update_plan';

  @override
  String get description => '更新当前执行计划：标记步骤完成、改写步骤文案或追加步骤。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('goal', description: '可选：更新后的任务目标'),
        ParamSpec.array(
          'todos',
          items: ParamSpec.object(
            'todo',
            properties: <String, ParamSpec>{
              'index': ParamSpec.integer('index', description: '步骤序号，从 1 起'),
              'text': ParamSpec.string('text', description: '新的步骤文案'),
              'done': ParamSpec.boolean('done', description: '是否已完成'),
            },
          ),
          description: '步骤更新列表；不带 index 的条目追加到末尾',
        ),
      ];

  @override
  Future<ToolResult> call(ToolContext context) async {
    final Plan? current = readPlan(session);
    if (current == null) {
      return ToolResult.failure(
        '尚无执行计划：请先调用 plan_write 制定计划。',
        error: const ToolError('NO_PLAN', 'no plan written yet'),
      );
    }
    final String? goal = context.string('goal');
    final List<Object?>? todos = context.array('todos');
    if (goal == null && (todos == null || todos.isEmpty)) {
      throw const ToolArgumentException('todos 为空且未提供 goal，无任何更新');
    }
    final UpdateResult updated = applyTodoUpdates(current.steps, todos);
    if (updated.errors.isNotEmpty) {
      return ToolResult.failure('部分更新未生效：\n${updated.errors.join('\n')}');
    }
    final Plan plan = Plan(
      goal: goal == null || goal.trim().isEmpty ? current.goal : goal.trim(),
      steps: updated.steps,
    );
    writePlan(session, plan);
    return ToolResult.success(plan.summary(), value: plan.toJson());
  }
}

/// 一次更新应用的结果：新步骤列表与未生效条目的错误。
class UpdateResult {
  const UpdateResult(this.steps, this.errors);

  final List<PlanStep> steps;
  final List<String> errors;
}

/// 应用 todo 更新：按 index 修改既有步骤，无 index 追加；违规记入 errors。
UpdateResult applyTodoUpdates(List<PlanStep> origin, List<Object?>? todos) {
  final List<PlanStep> steps = <PlanStep>[...origin];
  final List<String> errors = <String>[];
  if (todos == null) return UpdateResult(steps, errors);
  for (final Object? raw in todos) {
    final Map<String, Object?>? item = _asMap(raw);
    if (item == null) {
      errors.add('条目必须是对象 {index, text, done}');
      continue;
    }
    final int? index = _intOf(item['index']);
    if (index == null) {
      _appendStep(steps, item, errors);
    } else {
      _patchStep(steps, index, item, errors);
    }
  }
  return UpdateResult(steps, errors);
}

Map<String, Object?>? _asMap(Object? raw) =>
    raw is Map ? Map<String, Object?>.from(raw) : null;

int? _intOf(Object? value) => value is num ? value.toInt() : null;

void _appendStep(
    List<PlanStep> steps, Map<String, Object?> item, List<String> errors) {
  final String text = '${item['text'] ?? ''}'.trim();
  if (text.isEmpty) {
    errors.add('追加条目缺少 text');
    return;
  }
  steps.add(PlanStep(id: 's${steps.length + 1}', text: text));
}

void _patchStep(
    List<PlanStep> steps, int index, Map<String, Object?> item,
    List<String> errors) {
  if (index < 1 || index > steps.length) {
    errors.add('序号 $index 越界（当前 ${steps.length} 步）');
    return;
  }
  final PlanStep old = steps[index - 1];
  final Object? text = item['text'];
  final Object? done = item['done'];
  steps[index - 1] = PlanStep(
    id: old.id,
    text: text is String && text.isNotEmpty ? text : old.text,
    done: done is bool ? done : old.done,
  );
}

/// 把 `update_plan` 注册到 `ctx.tools`（对齐 `providePlanTool`）。
UpdatePlanTool provideUpdatePlanTool(
  Context ctx, {
  required Session session,
  ToolRegistry? tools,
}) {
  final ToolRegistry registry = tools ?? ctx.tools;
  final UpdatePlanTool tool = UpdatePlanTool(session: session);
  ctx.effect(() => registry.register(tool));
  return tool;
}
