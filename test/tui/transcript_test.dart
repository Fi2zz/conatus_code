/// 会话事件 → 屏上消息的投射。
library;

import 'dart:convert';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

void main() {
  test('回放会话事件：用户 / 工具调用 / 工具结果 / 助手', () {
    final Session session = Session(id: 's');
    session.append(kUserMessageEvent, data: <String, Object?>{'text': '几点？'});
    session.append(kAssistantMessageEvent, data: <String, Object?>{
      'text': '',
      'toolCalls': <Map<String, Object?>>[
        <String, Object?>{
          'id': '1',
          'name': 'get_time',
          'arguments': '{}',
        },
      ],
    });
    session.append(kToolResultEvent, data: <String, Object?>{
      'callId': '1',
      'name': 'get_time',
      'content': '12:00',
      'isError': false,
    });
    session.append(kAssistantMessageEvent,
        data: <String, Object?>{'text': '现在是 12:00。'});

    final Transcript transcript = Transcript()..rebuildFrom(session);

    expect(
      transcript.messages.map((TuiMessage m) => m.role).toList(),
      <TuiRole>[TuiRole.user, TuiRole.stage, TuiRole.tool, TuiRole.assistant],
    );
    expect(transcript.messages[1].text, contains('get_time'));
    expect(transcript.messages[2].text, contains('✓'));
    expect(transcript.messages[3].text, '现在是 12:00。');
  });

  test('失败的工具结果标记为 ✗ 并带内容预览', () {
    final Session session = Session(id: 's');
    session.append(kToolResultEvent, data: <String, Object?>{
      'callId': '1',
      'name': 'read_file',
      'content': '错误：文件不存在',
      'isError': true,
    });

    final Transcript transcript = Transcript()..rebuildFrom(session);

    expect(transcript.messages.single.role, TuiRole.tool);
    expect(transcript.messages.single.text, contains('✗'));
    expect(transcript.messages.single.text, contains('文件不存在'));
  });

  test('空助手事件（工具调用轮）不产生空气泡', () {
    final Session session = Session(id: 's');
    session.append(kAssistantMessageEvent,
        data: <String, Object?>{'text': '', 'toolCalls': <Object>[]});

    final Transcript transcript = Transcript()..rebuildFrom(session);

    expect(transcript.messages, isEmpty);
  });

  test('助手带文本的工具轮：文本与工具调用各成一行', () {
    final Session session = Session(id: 's');
    session.append(kAssistantMessageEvent, data: <String, Object?>{
      'text': '我先看看时间。',
      'toolCalls': <Map<String, Object?>>[
        <String, Object?>{'id': '1', 'name': 'get_time', 'arguments': '{}'},
      ],
    });

    final Transcript transcript = Transcript()..rebuildFrom(session);

    expect(
      transcript.messages.map((TuiMessage m) => m.role).toList(),
      <TuiRole>[TuiRole.assistant, TuiRole.stage],
    );
    expect(transcript.messages[0].text, '我先看看时间。');
    expect(transcript.messages[1].text, contains('get_time'));
  });

  test('助手事件携带 reasoning 时先渲染思考行', () {
    final Session session = Session(id: 's');
    session.append(kAssistantMessageEvent, data: <String, Object?>{
      'text': '回答。',
      'reasoning': '先分析再回答',
      'toolCalls': <Object>[],
    });

    final Transcript transcript = Transcript()..rebuildFrom(session);

    expect(
      transcript.messages.map((TuiMessage m) => m.role).toList(),
      <TuiRole>[TuiRole.thinking, TuiRole.assistant],
    );
    expect(transcript.messages[0].text, contains('先分析再回答'));
    expect(transcript.messages[1].text, '回答。');
  });

  test('工具结果正文保留完整多行内容', () {
    final Session session = Session(id: 's');
    session.append(kToolResultEvent, data: <String, Object?>{
      'callId': '1',
      'name': 'run_code',
      'content': '第一行\n第二行\n第三行',
      'isError': false,
    });

    final Transcript transcript = Transcript()..rebuildFrom(session);

    expect(transcript.messages.single.text, contains('第一行'));
    expect(transcript.messages.single.text, contains('第三行'));
  });

  test('计划事件生成 TODO 列表消息，默认展开，再次更新就地刷新', () {
    final Session session = Session(id: 's');
    session.append(kPlanEvent, data: <String, Object?>{
      'goal': '修 bug',
      'steps': <Map<String, Object?>>[
        <String, Object?>{'id': 's1', 'text': '复现', 'done': true},
        <String, Object?>{'id': 's2', 'text': '修复', 'done': false},
      ],
    });

    final Transcript transcript = Transcript()..rebuildFrom(session);

    final TuiMessage plan = transcript.planMessage!;
    expect(plan.role, TuiRole.plan);
    expect(plan.expanded, isTrue);
    expect(plan.text, contains('目标：修 bug'));
    expect(plan.text, contains('[x] 复现'));
    expect(plan.text, contains('[ ] 修复'));

    // 同一条消息就地更新，不新增。
    session.append(kPlanEvent, data: <String, Object?>{
      'goal': '修 bug',
      'steps': <Map<String, Object?>>[
        <String, Object?>{'id': 's1', 'text': '复现', 'done': true},
        <String, Object?>{'id': 's2', 'text': '修复', 'done': true},
      ],
    });
    transcript.apply(session.events.last);

    expect(transcript.messages.where((TuiMessage m) => m.role == TuiRole.plan),
        hasLength(1));
    expect(transcript.planMessage!.text, contains('[x] 修复'));
  });

  test('ctrl+t 折叠 / 展开 TODO 列表', () {
    final Session session = Session(id: 's');
    session.append(kPlanEvent, data: <String, Object?>{
      'goal': '修 bug',
      'steps': <Map<String, Object?>>[
        <String, Object?>{'id': 's1', 'text': '复现', 'done': false},
      ],
    });

    final Transcript transcript = Transcript()..rebuildFrom(session);

    expect(transcript.planMessage!.expanded, isTrue);
    transcript.togglePlanExpanded();
    expect(transcript.planMessage!.expanded, isFalse);
    transcript.togglePlanExpanded();
    expect(transcript.planMessage!.expanded, isTrue);
  });

  test('用户消息带图片时渲染占位块（序号 + 尺寸）', () {
    // 8 字节 PNG 签名 + IHDR 宽高（大端 683×416）。
    final List<int> png = <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      ...List<int>.filled(8, 0),
      0x00, 0x00, 0x02, 0xAB, // 683
      0x00, 0x00, 0x01, 0xA0, // 416
    ];
    final Session session = Session(id: 's');
    session.append(kUserMessageEvent, data: <String, Object?>{
      'text': '看下这张图',
      'images': imagesToJson(<LlmImage>[
        LlmImage(mimeType: 'image/png', base64Data: base64Encode(png)),
      ]),
    });

    final Transcript transcript = Transcript()..rebuildFrom(session);

    expect(transcript.messages.single.role, TuiRole.user);
    expect(transcript.messages.single.text, contains('看下这张图'));
    expect(transcript.messages.single.text, contains('[image #1 (683×416)]'));
  });

  test('流式思考边到边累积；事件 apply 内容一致时不重复追加', () {
    final Transcript transcript = Transcript();
    transcript.appendStream(reasoning: '想一');
    transcript.appendStream(reasoning: '想二');
    transcript.endStream();

    expect(transcript.messages, hasLength(1));
    expect(transcript.messages.single.text, '· 思考：想一想二');

    transcript.apply(SessionEvent(
      seq: 0,
      type: kAssistantMessageEvent,
      time: DateTime.fromMillisecondsSinceEpoch(0),
      data: <String, Object?>{
        'text': '',
        'reasoning': '想一想二',
        'toolCalls': <Object>[],
      },
    ));

    expect(transcript.messages, hasLength(1));
    expect(transcript.messages.single.text, '· 思考：想一想二');
  });

  test('新一步流式重置消息引用（不追加到上一步）', () {
    final Transcript transcript = Transcript();
    transcript.appendStream(reasoning: '第一步');
    transcript.endStream();
    transcript.appendStream(reasoning: '第二步');

    expect(transcript.messages, hasLength(2));
    expect(transcript.messages[0].text, '· 思考：第一步');
    expect(transcript.messages[1].text, '· 思考：第二步');
  });
}
