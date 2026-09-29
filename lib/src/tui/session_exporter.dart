/// 把会话导成 markdown（`/export`）。
///
/// 与 `/trace` 的分工：`/trace` 回答「刚才那轮发生了什么」，只管屏上能读的一屏；
/// `/export` 回答「把这次会话留下来」——存档、贴给同事、喂给别的工具分析。
/// 所以这里**不做内容截断**（截断是显示层的事），只留一个硬上限兜住病态输出。
library;

import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';

/// 单条工具结果的硬上限（字符）。
///
/// 导出本该是完整的，但一条 10MB 的 `rg` 结果能把 markdown 撑到没法看。超出的
/// 部分截掉并**显式标注被截了多少**——静默截断会让读的人以为那就是全部。
const int kExportMaxToolChars = 8000;

/// 一次会话导出。
class SessionExport {
  SessionExport({
    required this.session,
    required this.modelLabel,
    this.workdir = '',
    this.cost = 0,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.rateSummary = '',
  });

  /// 会话。
  final Session session;

  /// 导出时正在用的模型标签。
  final String modelLabel;

  /// 工作目录。
  final String workdir;

  /// 累计成本（美元）。
  final double cost;

  /// 累计输入 token。
  final int promptTokens;

  /// 累计输出 token。
  final int completionTokens;

  /// 费率来源说明（来自 models.dev 时带上，否则「未知」）。
  final String rateSummary;

  /// 渲染成 markdown。
  String toMarkdown() {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('# nava 会话 ${session.id}');
    buffer.writeln();
    buffer.writeln(_header());
    buffer.writeln();
    for (final SessionEvent event in session.ownEvents) {
      _writeEvent(buffer, event);
    }
    return buffer.toString();
  }

  /// 缺省导出文件名：`<会话 id 去掉 session_ 前缀>.md`。
  String get defaultFileName {
    final String bare = session.id.startsWith('session_')
        ? session.id.substring('session_'.length)
        : session.id;
    return 'nava-$bare.md';
  }

  /// 落盘。返回最终绝对路径。
  ///
  /// [target] 缺省时写到项目数据目录下的 `exports/`——**不放工作区**。理由与
  /// 会话/检查点一致：导出是工具的产物，不该在用户的代码仓库里留垃圾。给绝对
  /// 路径或 `~` 开头的路径则照用户给的位置写。
  Future<String> write({
    String? target,
    required String projectDataDir,
    Map<String, String>? env,
  }) async {
    final String path = resolveExportPath(
      target: target,
      projectDataDir: projectDataDir,
      fileName: defaultFileName,
      env: env,
    );
    // 同 id 重复导出会覆盖；这是合理的（重导一次是想要最新版），不做成报错。
    final File file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(toMarkdown());
    return file.absolute.path;
  }

  String _header() {
    final List<String> rows = <String>[
      '- 会话：`${session.id}`',
      '- 开始：${session.createdAt.toLocal().toIso8601String().split('.').first}',
      '- 模型：$modelLabel',
      if (workdir.isNotEmpty) '- 工作目录：`$workdir`',
      '- 事件：${session.ownEvents.length} 条',
      if (promptTokens > 0 || completionTokens > 0)
        '- token：输入 $promptTokens / 输出 $completionTokens',
      if (rateSummary.isNotEmpty) '- 费率：$rateSummary',
      if (cost > 0) '- 成本：\$${cost.toStringAsFixed(4)}（models.dev 口径，非账单）',
    ];
    return rows.join('\n');
  }

  void _writeEvent(StringBuffer buffer, SessionEvent event) {
    final Object? data = event.data;
    switch (event.type) {
      case kUserMessageEvent:
        buffer
          ..writeln('## 你')
          ..writeln()
          ..writeln(_text(data))
          ..writeln();
      case kAssistantMessageEvent:
        _writeAssistant(buffer, data);
      case kToolResultEvent:
        _writeToolResult(buffer, data);
      case 'compaction/start':
        buffer
          ..writeln('> 早期历史已折叠成摘要')
          ..writeln();
      case 'compaction/end':
        if (data is Map && data['error'] != null) {
          buffer
            ..writeln('> **压缩失败**：${data['error']}')
            ..writeln();
        }
      default:
        return; // 内部事件不进导出。
    }
  }

  void _writeAssistant(StringBuffer buffer, Object? data) {
    if (data is! Map) return;
    final String reasoning = '${data['reasoning'] ?? ''}'.trim();
    final String text = _text(data);
    if (reasoning.isNotEmpty) {
      buffer
        ..writeln('<details><summary>思考</summary>')
        ..writeln()
        ..writeln(reasoning)
        ..writeln()
        ..writeln('</details>')
        ..writeln();
    }
    if (text.trim().isNotEmpty) {
      buffer
        ..writeln('## 助手')
        ..writeln()
        ..writeln(text)
        ..writeln();
    }
  }

  void _writeToolResult(StringBuffer buffer, Object? data) {
    if (data is! Map) return;
    final String name = '${data['name'] ?? ''}';
    if (name.isEmpty) return;
    final bool failed = data['isError'] == true;
    final String body = _clipTool('${data['content'] ?? ''}');
    buffer
      ..writeln('### ${failed ? '✗' : '✓'} $name')
      ..writeln()
      ..writeln('```')
      ..writeln(body)
      ..writeln('```')
      ..writeln();
  }

  /// 工具结果正文；超上限时截断并说明丢了多少。
  String _clipTool(String text) {
    final String body = text.trimRight();
    if (body.length <= kExportMaxToolChars) return body;
    return '$body\n\n…（已截断，共 ${body.length} 字符，'
        '保留前 $kExportMaxToolChars）';
  }

  static String _text(Object? data) =>
      data is Map ? '${data['text'] ?? ''}'.trim() : '';
}

/// 解析导出落点。
///
/// 缺省落项目数据目录的 `exports/`，**不在工作区建文件**——与会话 / 检查点
/// 同一取舍：导出是工具产物，不该往用户的代码仓库里留垃圾。用户给了路径就照
/// 给的位置写（支持 `~` 展开）。
String resolveExportPath({
  String? target,
  required String projectDataDir,
  required String fileName,
  Map<String, String>? env,
}) {
  final String? requested = _clean(target);
  if (requested == null) {
    return '$projectDataDir${Platform.pathSeparator}exports'
        '${Platform.pathSeparator}$fileName';
  }
  final String home = _home(env) ?? '';
  final String expanded = home.isNotEmpty && requested.startsWith('~')
      ? home + requested.substring(1)
      : requested;
  // 指向目录（以分隔符结尾）时按目录处理，补上文件名。
  if (expanded.endsWith(Platform.pathSeparator) ||
      expanded.endsWith('/')) {
    return '$expanded$fileName';
  }
  return expanded;
}

String? _clean(String? value) {
  final String? trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

String? _home(Map<String, String>? env) =>
    _clean(env?['HOME'] ?? Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE']);
