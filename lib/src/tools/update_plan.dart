/// todowrite 工具：执行中推进 / 修订当前会话的执行计划。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

/// `todowrite` 工具：无计划时用 `goal + todos` 创建，已有计划时按序号更新。
///
/// 序号与计划面板 / system prompt 里的「1. [ ] text」一致；不带 `index` 的
/// 条目追加到末尾。写入统一回 `plan/updated` 事件，面板与后续摘要即时反映。
class UpdatePlanTool extends Tool {
  UpdatePlanTool({required this.session});

  /// 计划持久化到的会话。
  final Session session;

  @override
  String get name => 'todowrite';

  @override
  String get description => '制定或更新当前执行计划：无计划时用 goal + todos 创建；'
      '已有计划时标记完成、改写文案或追加步骤。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('goal', description: '任务目标（创建计划时必填）'),
        ParamSpec.array(
          'todos',
          items: ParamSpec.object(
            'todo',
            properties: <String, ParamSpec>{
              'index': ParamSpec.integer('index', description: '步骤序号，从 1 起'),
              'text': ParamSpec.string('text', description: '步骤文案'),
              'done': ParamSpec.boolean('done', description: '是否已完成'),
            },
          ),
          description: '无计划时作为初始步骤；已有计划时按 index 更新，不带 index 的条目追加',
        ),
      ];

  @override
  Future<ToolResult> call(ToolContext context) async {
    final String? goal = context.string('goal')?.trim();
    final List<Object?>? todos = context.array('todos');
    final Plan? current = readPlan(session);
    if (current == null) {
      return _createPlan(goal: goal, todos: todos);
    }
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

  /// 无计划时用 `goal + todos` 创建初始计划。
  ToolResult _createPlan({
    required String? goal,
    required List<Object?>? todos,
  }) {
    if (goal == null || goal.isEmpty) {
      return ToolResult.failure(
        '尚无执行计划：用 goal + todos 创建计划。',
        error: const ToolError('NO_PLAN', 'no plan written yet'),
      );
    }
    final UpdateResult created = _createdSteps(todos);
    if (created.errors.isNotEmpty) {
      return ToolResult.failure('计划未创建：\n${created.errors.join('\n')}');
    }
    if (created.steps.isEmpty) {
      return ToolResult.failure(
        '尚无执行计划：todos 为空，无法创建。',
        error: const ToolError('NO_PLAN', 'no plan steps'),
      );
    }
    final Plan plan = Plan(goal: goal, steps: created.steps);
    writePlan(session, plan);
    return ToolResult.success(plan.summary(), value: plan.toJson());
  }
}

/// 把初始 todos 转成计划步骤；缺 text 的条目记入 errors。
UpdateResult _createdSteps(List<Object?>? todos) {
  final List<PlanStep> steps = <PlanStep>[];
  final List<String> errors = <String>[];
  for (final Object? raw in todos ?? const <Object?>[]) {
    final Map<Object?, Object?>? item =
        raw is Map ? Map<Object?, Object?>.from(raw) : null;
    final String text = switch (raw) {
      final String value => value.trim(),
      final Map<Object?, Object?> value => '${value['text'] ?? ''}'.trim(),
      _ => '',
    };
    if (text.isEmpty) {
      errors.add('初始步骤缺少 text');
      continue;
    }
    steps.add(PlanStep(
      id: 's${steps.length + 1}',
      text: text,
      done: item?['done'] == true,
    ));
  }
  return UpdateResult(steps, errors);
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

/// 把 `todowrite` 注册到 `ctx.tools`。
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
