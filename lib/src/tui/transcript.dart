/// 屏上记录：把 conatus 会话事件投射为可渲染的消息流。
///
/// 与参考的「气泡镜像」不同，这里直接以 [SessionEvent] 为唯一事实源：
/// 用户 / 助手 / 工具 / 计划各自渲染成一行，绑定会话时回放历史事件，
/// 之后由 [apply] 增量追加，因此与持久化历史天然一致。
library;

import 'dart:convert';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';

import 'tui_attachment.dart';
import 'tui_message.dart';
import 'tui_skill_command.dart';

/// 屏上记录。
class Transcript {
  /// 屏上消息（按发生顺序）。
  final List<TuiMessage> messages = <TuiMessage>[];

  /// `/help` 弹出的帮助消息（Esc 可关闭）；null = 未打开。
  TuiMessage? help;

  /// 当前计划的 TODO 列表消息（`plan/updated` 时新建或就地更新）。
  TuiMessage? _plan;

  /// 流式渲染：当前步的思考 / 正文消息引用（delta 边到边追加到同一条）。
  TuiMessage? _streamThinking;
  TuiMessage? _streamAssistant;

  /// 流式是否进行中（endStream 后下一步的首个 delta 重建消息引用）。
  bool _streamLive = false;

  /// 清空屏上记录（不改动会话数据）。
  void clear() {
    messages.clear();
    help = null;
    _plan = null;
    _streamThinking = null;
    _streamAssistant = null;
    _streamLive = false;
  }

  /// 追加一条消息。
  void add(TuiRole role, String text) => messages.add(TuiMessage(role, text));

  /// 当前计划的 TODO 列表消息；尚无计划为 `null`。
  TuiMessage? get planMessage => _plan;

  /// 展开 / 收起 TODO 列表（ctrl+t）；无计划不动作。
  void togglePlanExpanded() {
    final TuiMessage? message = _plan;
    if (message == null) {
      return;
    }
    message.expanded = !message.expanded;
  }

  /// 打开帮助弹出并记录引用，供 [closeHelp] 移除；已打开时先关闭旧的。
  void openHelp(String text) {
    closeHelp();
    help = TuiMessage(TuiRole.system, text);
    messages.add(help!);
  }

  /// 关闭帮助弹出；未打开返回 false。
  bool closeHelp() {
    final TuiMessage? message = help;
    if (message == null) {
      return false;
    }
    messages.remove(message);
    help = null;
    return true;
  }

  /// 绑定会话：按持久化事件回放整段历史。
  void rebuildFrom(Session session) {
    messages.clear();
    help = null;
    _plan = null;
    _streamThinking = null;
    _streamAssistant = null;
    _streamLive = false;
    for (final SessionEvent event in session.events) {
      apply(event);
    }
  }

  /// 追加流式增量：同一步的 delta 边到边累积进同一条思考 / 正文消息；
  /// 新一步的首个 delta 自动重建消息引用（上一步的引用已被 apply 消费）。
  void appendStream({String reasoning = '', String text = ''}) {
    if (!_streamLive) {
      _streamThinking = null;
      _streamAssistant = null;
      _streamLive = true;
    }
    if (reasoning.isNotEmpty) {
      final TuiMessage? current = _streamThinking;
      if (current == null) {
        final TuiMessage message =
            TuiMessage(TuiRole.thinking, '· 思考：$reasoning');
        _streamThinking = message;
        messages.add(message);
      } else {
        current.text += reasoning;
      }
    }
    if (text.isNotEmpty) {
      final TuiMessage? current = _streamAssistant;
      if (current == null) {
        final TuiMessage message = TuiMessage(TuiRole.assistant, text);
        _streamAssistant = message;
        messages.add(message);
      } else {
        current.text += text;
      }
    }
  }

  /// 流式结束（一步收口）：保留消息引用供随后的 assistant 事件 apply 去重。
  void endStream() {
    _streamLive = false;
  }

  /// 增量投射一条会话事件。
  void apply(SessionEvent event) {
    final Object? data = event.data;
    switch (event.type) {
      case kUserMessageEvent:
        add(TuiRole.user, '${collapseSkillPrompt(_text(data))}${_imageMarker(data)}');
      case kAssistantMessageEvent:
        // 思考过程（Kimi 等 `reasoning_content`）先单独成行，再是正文与
        // 工具调用名；流式已实时显示的内容（引用文本一致）不重复追加。
        final String reasoning = _field(data, 'reasoning').trim();
        if (reasoning.isNotEmpty) {
          final TuiMessage? streamed = _streamThinking;
          if (streamed == null || streamed.text != '· 思考：$reasoning') {
            add(TuiRole.thinking, '· 思考：$reasoning');
          }
        }
        final String text = _text(data);
        if (text.trim().isNotEmpty) {
          final TuiMessage? streamed = _streamAssistant;
          if (streamed == null || streamed.text != text) {
            add(TuiRole.assistant, text);
          }
        }
        for (final LlmToolCall call in _toolCalls(data)) {
          add(TuiRole.stage, '· 调用工具 ${call.name}');
        }
      case kToolResultEvent:
        final String name = _field(data, 'name');
        final bool failed = data is Map && data['isError'] == true;
        final String mark = failed ? '✗' : '✓';
        // 完整内容存进消息正文；过长时由视图折叠，ctrl+o 展开。
        final String content = _field(data, 'content').trim();
        add(TuiRole.tool, content.isEmpty
            ? '· 工具 $mark $name'
            : '· 工具 $mark $name\n$content');
      case kPlanEvent:
        _upsertPlan(data);
      default:
        // 其余事件（含自定义）不投射。
        return;
    }
  }

  /// 计划事件：把 TODO 列表消息设为当前计划（无则新建，有则就地更新正文），
  /// 默认展开显示完整步骤，ctrl+t 折叠。
  void _upsertPlan(Object? data) {
    if (data is! Map) {
      return;
    }
    final Plan plan = Plan.fromJson(Map<String, Object?>.from(data));
    final TuiMessage? current = _plan;
    final TuiMessage message =
        current ?? (TuiMessage(TuiRole.plan, '')..expanded = true);
    message.text = plan.summary();
    if (current == null) {
      _plan = message;
      messages.add(message);
    }
  }

  static String _text(Object? data) => _field(data, 'text');

  static String _field(Object? data, String key) {
    if (data is Map) {
      final Object? value = data[key];
      return value == null ? '' : '$value';
    }
    return '';
  }

  static List<LlmToolCall> _toolCalls(Object? data) {
    if (data is Map) return toolCallsFromJson(data['toolCalls']);
    return const <LlmToolCall>[];
  }

  /// 用户消息携带图片时追加的屏上标记（如 ` [图片 ×2]`）。
  /// 图片占位块：每条图片跟随用户消息正文，独立成行 `[image #N (宽×高)]`
  /// （尺寸从图片字节解析；解析不到则省略尺寸段）。
  static String _imageMarker(Object? data) {
    if (data is! Map) return '';
    final List<LlmImage> images = imagesFromJson(data['images']);
    if (images.isEmpty) return '';
    final List<String> blocks = <String>[
      for (int index = 0; index < images.length; index++)
        '[image #${index + 1}${_imageDims(images[index])}]',
    ];
    return '\n${blocks.join('\n')}';
  }

  /// 从图片 base64 字节解析 `宽×高`；失败返回空串。
  static String _imageDims(LlmImage image) {
    final String? dims = imageDimensions(base64Decode(image.base64Data));
    return dims == null ? '' : ' ($dims)';
  }
}
