/// 启动技能：把一个或多个技能的完整正文挂成常驻 system prompt 段。
///
/// 普通技能只把「名字 + 描述」放进目录，等模型调用 `skill` 工具再取正文；
/// 启动技能在装配期直接加载正文，适合 `using-superpowers` 这类协议型技能。
library;

import 'dart:async';

import 'package:conatus_core/conatus_core.dart' show Disposer;
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_skill/conatus_skill.dart';

/// 启动技能段的默认名字。
const String kSkillBootstrapSectionName = 'skill-bootstrap';

/// 启动技能段的排序权重：紧跟技能目录之后。
const int kSkillBootstrapOrder = 51;

/// 渲染启动技能块。
String renderSkillBootstrap(
  List<SkillDefinition> definitions, {
  String appendix = '',
}) {
  final String names = definitions
      .map((SkillDefinition item) => item.summary.name)
      .join(', ');
  final StringBuffer buffer = StringBuffer()
    ..write('<EXTREMELY_IMPORTANT>\n')
    ..write('You have superpowers.\n\n')
    ..write(
      '**IMPORTANT: The following bootstrap skills are ALREADY LOADED: '
      '$names. Do NOT call the `skill` tool to load them again.**\n\n',
    );
  for (final SkillDefinition definition in definitions) {
    _writeSkill(buffer, definition);
  }
  final String extra = appendix.trim();
  if (extra.isNotEmpty) {
    buffer
      ..write(extra)
      ..write('\n');
  }
  buffer.write('</EXTREMELY_IMPORTANT>');
  return buffer.toString();
}

void _writeSkill(StringBuffer buffer, SkillDefinition definition) {
  final SkillSummary summary = definition.summary;
  buffer
    ..write('<skill name="')
    ..write(escapeSkillAttribute(summary.name))
    ..write('">\n')
    ..write(renderSkillResourceHint(definition.resourceBase, summary.provider))
    ..write('\n\n')
    ..write(definition.content.trim())
    ..write('\n</skill>\n\n');
}

/// 跟随技能注册表，把 [names] 的正文挂成常驻 prompt 段。
class SkillBootstrapSection {
  SkillBootstrapSection({
    required this.registry,
    required this.prompt,
    required this.names,
    this.appendix = '',
    this.order = kSkillBootstrapOrder,
  });

  final SkillRegistry registry;
  final SystemPrompt prompt;

  /// 要加载的技能名；未知技能会被跳过。
  final List<String> names;

  /// 追加在技能正文后的工具映射或其他说明。
  final String appendix;

  final int order;

  Disposer? _section;
  Disposer? _listener;
  String? _text;
  Future<void>? _running;
  bool _dirty = false;
  bool _disposed = false;

  /// 加载并挂段，同时监听注册表变化；返回的 Future 在首次加载完成后收口。
  Future<void> start() async {
    _listener ??= registry.onChange(_schedule);
    await refresh();
  }

  /// 重新加载全部启动技能；并发调用合并，期间的变化会在结束后补跑一次。
  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    final Future<void>? running = _running;
    if (running != null) {
      _dirty = true;
      return running;
    }
    final Future<void> future = _load();
    _running = future.whenComplete(() {
      _running = null;
      if (_dirty && !_disposed) {
        _dirty = false;
        unawaited(refresh());
      }
    });
    return _running!;
  }

  /// 撤销监听与 prompt 段（幂等）。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _listener?.call();
    _listener = null;
    _section?.call();
    _section = null;
    _text = null;
  }

  void _schedule() {
    unawaited(refresh());
  }

  Future<void> _load() async {
    final List<SkillDefinition> definitions = <SkillDefinition>[];
    for (final String name in names) {
      final SkillDefinition? definition = await registry.load(name);
      if (definition != null) definitions.add(definition);
    }
    if (_disposed) return;
    if (definitions.isEmpty) {
      _text = null;
      _section?.call();
      _section = null;
      return;
    }
    _text = renderSkillBootstrap(definitions, appendix: appendix);
    _section ??= prompt.section(
      PromptSection(
        name: kSkillBootstrapSectionName,
        order: order,
        text: () => _text ?? '',
      ),
    );
  }
}

/// nava 的工具映射；启动技能正文里的动作按这张表落到实际工具。
const String kNavaSkillToolMapping = '''
**Tool Mapping for nava:**
When a skill requests an action, substitute the nava equivalent:
- Invoke a skill -> the `skill` tool. Use the bare kebab-case name
  (`brainstorming`), never the `superpowers:` prefix.
- Read a file -> `read_file`; write -> `write_file`; edit -> `edit_file` or
  `apply_patch`.
- Run a shell command -> `run_command`; search contents -> `rg`; find files ->
  `glob`; list a directory -> `list_files`.
- Dispatch a subagent -> `spawn_agent` with `task`; `agent` is only for a
  registered profile. Do not invent a `subagent_type` argument.
- Track tasks -> `plan_write` to create the plan and `update_plan` to advance
  it; nava has no TodoWrite tool. A markdown checklist is an acceptable fallback.
- Fetch a URL -> `fetch_url`; search the web -> `web_search`.
- "Your instructions file" -> `AGENTS.md` (project root or `~/.nava/AGENTS.md`).

Use the `skill` tool for other available skills listed in the catalog.''';
