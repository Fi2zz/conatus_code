/// TUI 渲染件：消息行、思考占位行与若干展示工具。
library;

import 'package:nocterm/nocterm.dart';

import 'tui_message.dart';

/// 思考中动画帧。
const List<String> tuiSpinFrames = <String>[
  '⠋',
  '⠙',
  '⠹',
  '⠸',
  '⠼',
  '⠴',
  '⠦',
  '⠧',
  '⠇',
  '⠏',
];

/// 当前动画帧。
String tuiSpinner(int tick) => tuiSpinFrames[tick % tuiSpinFrames.length];

/// 动态省略号（纯 ASCII，兼容不显示盲文点的终端）。
String tuiDots(int tick) => '.' * (tick % 4);
const String tuiDot = '.';

/// 相对时间描述（用于会话面板）。
String timeAgo(DateTime? time) {
  if (time == null) {
    return '未知';
  }
  final Duration diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) {
    return '刚刚';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes}分钟前';
  }
  if (diff.inDays < 1) {
    return '${diff.inHours}小时前';
  }
  return '${diff.inDays}天前';
}

/// 一条屏上消息：用户 / 助手带前缀，工具 / 阶段 / 系统 / 导航为缩进提示行。
class MessageView extends StatelessComponent {
  const MessageView({super.key, required this.message});

  /// 要渲染的消息。
  final TuiMessage message;

  @override
  Component build(BuildContext context) {
    switch (message.role) {
      case TuiRole.user:
        return _line(
          Text(message.text, style: const TextStyle(color: Colors.white)),
        );
      case TuiRole.assistant:
        return _line(MarkdownText(message.text));
      case TuiRole.tool:
        return _indent(_foldTool(message), Colors.cyan);
      case TuiRole.plan:
        return _indent(_foldPlan(message), Colors.brightBlue);
      case TuiRole.thinking:
        return _indent(_foldThinking(message), Colors.brightBlack);
      case TuiRole.stage:
        return _indent(message.text, Colors.brightBlack);
      case TuiRole.system:
        return _indent(message.text, Colors.yellow);
      case TuiRole.nav:
        return _indent(message.text, Colors.magenta);
    }
  }

  /// 一条顶格消息（用户 / 助手正文，无「你：/助手：」气泡前缀，
  /// 与 kimi-code 的记录风格一致）。
  Component _line(Component body) {
    return Padding(padding: const EdgeInsets.only(left: 2), child: body);
  }

  Component _indent(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(text, style: TextStyle(color: color)),
    );
  }

  /// 工具结果正文：折叠时只显示前 [kToolPreviewLines] 行并提示，展开显示全文。
  String _foldTool(TuiMessage message) {
    final List<String> lines = message.text.split('\n');
    if (message.expanded || lines.length <= kToolPreviewLines) {
      return message.text;
    }
    final String head = lines.take(kToolPreviewLines).join('\n');
    return '$head\n…（已折叠，共 ${lines.length} 行，按 ctrl+o 展开）';
  }

  /// TODO 列表：默认展开显示完整步骤；折叠成一行摘要（ctrl+t 展开）。
  String _foldPlan(TuiMessage message) {
    if (message.expanded) {
      return message.text;
    }
    final List<String> lines = message.text.split('\n');
    final String goal = lines.isEmpty ? '' : lines.first;
    final int steps = lines.length > 1 ? lines.length - 1 : 0;
    return '$goal（$steps 步 · 按 ctrl+t 展开）';
  }

  /// 思考过程：折叠时只显示前 [kToolPreviewLines] 行并提示，展开显示全文。
  String _foldThinking(TuiMessage message) {
    final List<String> lines = message.text.split('\n');
    if (message.expanded || lines.length <= kToolPreviewLines) {
      return message.text;
    }
    final String head = lines.take(kToolPreviewLines).join('\n');
    return '$head\n…（思考共 ${lines.length} 行，按 ctrl+o 展开）';
  }
}

/// 思考占位行：等待模型回复期间显示在记录末尾。
class LoadingView extends StatelessComponent {
  const LoadingView({super.key, required this.tick});

  /// 动画帧计数。
  final int tick;

  @override
  Component build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        '${tuiSpinner(tick)} 思考中${tuiDots(tick)}',
        style: const TextStyle(color: Colors.brightYellow),
      ),
    );
  }
}
