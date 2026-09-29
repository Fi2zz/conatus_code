/// 把会话事件渲染成可读的复盘文本（`/trace` 的正文）。
///
/// 会话日志本来就是可读 JSONL、事件也全都在盘上——缺的不是数据，是**能看的
/// 入口**。模型干了件蠢事时，你要回答的是「它当时看到了什么、为什么那么判断」，
/// 而屏上只有结论。这里把一轮的事件按时间线摊平，失败项标出来。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

/// 复盘渲染器。
class TraceRenderer {
  const TraceRenderer({this.toolResultChars = 160});

  /// 工具结果正文在每条里的截断长度。
  ///
  /// 全文塞进来会把屏刷爆，而复盘要的是「它看到了什么形状的东西」——头几行
  /// 足够判断，完整内容去读 JSONL。
  final int toolResultChars;

  /// 渲染最近 [turns] 轮（按 `user/message` 切轮）。
  ///
  /// [turns] 为 null 时只渲染最后一轮。
  String render(List<SessionEvent> events, {int? turns}) {
    final List<SessionEvent> window = _window(events, turns);
    if (window.isEmpty) return '本会话还没有可复盘的事件。';
    final StringBuffer buffer = StringBuffer();
    for (final SessionEvent event in window) {
      final String? rendered = line(event);
      if (rendered != null) buffer.writeln(rendered);
    }
    if (buffer.isEmpty) {
      return '最近这轮没有工具调用或模型输出（只有事件记录）。';
    }
    return buffer.toString().trimRight();
  }

  /// 取最近 [turns] 轮的事件；null = 最后一轮。
  List<SessionEvent> _window(List<SessionEvent> events, int? turns) {
    if (events.isEmpty) return const <SessionEvent>[];
    final List<int> starts = <int>[
      for (int i = 0; i < events.length; i++)
        if (events[i].type == kUserMessageEvent) i,
    ];
    if (starts.isEmpty) return events;
    final int from = turns == null || turns < 1
        ? starts.last
        : starts[starts.length - turns.clamp(1, starts.length)];
    return events.sublist(from);
  }

  /// 单个事件 → 一行；不该展示的类型返回 `null`。
  String? line(SessionEvent event) {
    final Object? data = event.data;
    return switch (event.type) {
      kUserMessageEvent => '你 › ${_clip(_text(data), 100)}',
      kAssistantMessageEvent => _assistantLine(data),
      kToolResultEvent => _toolResultLine(data),
      'compaction/start' => '── 压缩开始（早期历史折叠成摘要）',
      'compaction/end' =>
        data is Map && data['error'] != null
            ? '✗ 压缩失败：${data['error']}'
            : '── 压缩结束',
      _ => null,
    };
  }

  String? _assistantLine(Object? data) {
    if (data is! Map) return null;
    final String reasoning = _field(data, 'reasoning').trim();
    final String text = _text(data).trim();
    final List<String> parts = <String>[];
    if (reasoning.isNotEmpty) {
      parts.add('思考 › ${_clip(reasoning, 100)}');
    }
    if (text.isNotEmpty) parts.add('助手 › ${_clip(text, 100)}');
    if (parts.isEmpty) return null;
    return parts.join('\n');
  }

  String? _toolResultLine(Object? data) {
    if (data is! Map) return null;
    final String name = _field(data, 'name');
    if (name.isEmpty) return null;
    final bool failed = data['isError'] == true;
    final String mark = failed ? '✗' : '✓';
    return '$mark $name › ${_clip(_field(data, 'content').trim(), toolResultChars)}';
  }

  /// 工具结果正文：取首行 + 报出总行数。
  ///
  /// 只取首行是为了不刷屏，但**必须带上行数**——`rg` 命中 12 处和 1 处是完全
  /// 不同的两种情况，砍到首行就把这个信息丢了，而行数正是复盘时最想先看的。
  static String _clip(String text, int limit) {
    final List<String> lines = text
        .trim()
        .split('\n')
        .where((String l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return '（空）';
    final String first = lines.first.trim();
    final String head =
        first.length <= limit ? first : '${first.substring(0, limit)}…';
    if (lines.length == 1) return head;
    return '$head（+${lines.length - 1} 行）';
  }

  static String _text(Object? data) =>
      data is Map ? '${data['text'] ?? ''}' : '';

  static String _field(Object? data, String key) =>
      data is Map ? '${data[key] ?? ''}' : '';
}
