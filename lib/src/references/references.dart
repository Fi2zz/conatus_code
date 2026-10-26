/// 命名外部目录（references）：解析、system prompt 与只读边界。
library;

import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import '../config/config_schema.dart';

/// prompt 段名字。
const String kReferenceSectionName = 'references';

/// prompt 段排序（在项目指令之后、技能目录之前）。
const int kReferenceSectionOrder = 45;

/// 已解析的 reference（绝对真实路径）。
class ResolvedReference {
  const ResolvedReference({
    required this.name,
    required this.path,
    required this.description,
  });

  final String name;
  final String path;
  final String description;
}

/// 解析配置里的 references；缺失 / 非目录只告警跳过。
List<ResolvedReference> resolveReferences(
  List<ReferenceConfig> references, {
  required String workdir,
  void Function(String message)? onWarning,
}) {
  final List<ResolvedReference> result = <ResolvedReference>[];
  for (final ReferenceConfig reference in references) {
    final String? path = _resolve(reference.path, workdir);
    if (path == null) {
      onWarning?.call(
        'reference "${reference.name}" 的目录不可用：${reference.path}',
      );
      continue;
    }
    result.add(
      ResolvedReference(
        name: reference.name,
        path: path,
        description: reference.description,
      ),
    );
  }
  return result;
}

String? _resolve(String raw, String workdir) {
  String value = raw.trim();
  if (value.isEmpty) return null;
  if (value == '~') {
    value = resolveHomeDir();
  } else if (value.startsWith('~/')) {
    value = '${resolveHomeDir()}/${value.substring(2)}';
  } else if (!value.startsWith('/')) {
    value = '$workdir${Platform.pathSeparator}$value';
  }
  final Directory directory = Directory(value);
  if (!directory.existsSync()) return null;
  try {
    return directory.resolveSymbolicLinksSync();
  } on FileSystemException {
    return null;
  }
}

/// 把 references 挂成 system prompt 段；空列表不注册。
void provideReferencePrompt(
  Context ctx,
  List<ResolvedReference> references,
) {
  if (references.isEmpty) return;
  final SystemPrompt prompt = ctx.require<SystemPrompt>('systemPrompt');
  final PromptSection section = PromptSection(
    name: kReferenceSectionName,
    order: kReferenceSectionOrder,
    text: () => renderReferences(references),
  );
  ctx.effect(() => prompt.section(section));
}

/// 渲染 references 段。
String renderReferences(List<ResolvedReference> references) {
  final StringBuffer buffer = StringBuffer(
    '<references>\n'
    'These directories are read-only references. Use read_file / rg / glob '
    'with the absolute paths below when the task needs them.\n',
  );
  for (final ResolvedReference reference in references) {
    buffer.write('- ${_escape(reference.name)}: ${_escape(reference.path)}');
    if (reference.description.isNotEmpty) {
      buffer.write(' — ${_escape(reference.description)}');
    }
    buffer.write('\n');
  }
  buffer.write('</references>');
  return buffer.toString();
}

String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
