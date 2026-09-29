/// `/trace` 复盘渲染：把会话事件摊成可读时间线。
library;

import 'package:conatus_code/tui.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

SessionEvent _event(int seq, String type, [Map<String, Object?>? data]) =>
    SessionEvent(
      seq: seq,
      type: type,
      time: DateTime.utc(2026),
      data: data,
    );

List<SessionEvent> _oneTurn() => <SessionEvent>[
      _event(0, kUserMessageEvent, <String, Object?>{'text': '修一下 bug'}),
      _event(1, kAssistantMessageEvent, <String, Object?>{
        'text': '',
        'reasoning': '先看文件',
        'toolCalls': <Object?>[
          <String, Object?>{'id': 'c1', 'name': 'read_file'},
        ],
      }),
      _event(2, kToolResultEvent, <String, Object?>{
        'name': 'read_file',
        'content': 'void main() {}',
        'isError': false,
      }),
      _event(3, kToolResultEvent, <String, Object?>{
        'name': 'edit_file',
        'content': 'boom: permission denied',
        'isError': true,
      }),
      _event(4, kAssistantMessageEvent, <String, Object?>{
        'text': '改完了',
        'reasoning': '',
        'toolCalls': const <Object?>[],
      }),
    ];

void main() {
  group('TraceRenderer', () {
    const TraceRenderer renderer = TraceRenderer();

    test('按时间线渲染一轮：输入 / 思考 / 工具 / 输出', () {
      final String text = renderer.render(_oneTurn());

      expect(text, contains('你 › 修一下 bug'));
      expect(text, contains('思考 › 先看文件'));
      expect(text, contains('✓ read_file › void main() {}'));
      expect(text, contains('助手 › 改完了'));
    });

    // 失败项是复盘的重点：模型为什么停下、哪一步炸了。
    test('失败的工具结果标 ✗ 并带出原因', () {
      final String text = renderer.render(_oneTurn());

      expect(text, contains('✗ edit_file › boom: permission denied'));
    });

    test('不可读的事件被跳过（不产生噪声行）', () {
      final String text = renderer.render(<SessionEvent>[
        _event(0, kUserMessageEvent, <String, Object?>{'text': 'x'}),
        _event(1, 'agent/round', <String, Object?>{'step': 0}),
        _event(2, 'plan/updated', <String, Object?>{'plan': '[]'}),
      ]);

      expect(text, contains('你 › x'));
      expect(text.contains('agent/round'), isFalse);
      expect(text.contains('plan/updated'), isFalse);
    });

    test('缺省只渲染最后一轮', () {
      final List<SessionEvent> events = <SessionEvent>[
        _event(0, kUserMessageEvent, <String, Object?>{'text': '第一轮'}),
        _event(1, kAssistantMessageEvent, <String, Object?>{'text': '答一'}),
        _event(2, kUserMessageEvent, <String, Object?>{'text': '第二轮'}),
        _event(3, kAssistantMessageEvent, <String, Object?>{'text': '答二'}),
      ];

      final String text = renderer.render(events);

      expect(text, contains('第二轮'));
      expect(text, contains('答二'));
      expect(text.contains('第一轮'), isFalse);
    });

    test('turns=N 渲染最近 N 轮', () {
      final List<SessionEvent> events = <SessionEvent>[
        _event(0, kUserMessageEvent, <String, Object?>{'text': '一'}),
        _event(1, kUserMessageEvent, <String, Object?>{'text': '二'}),
        _event(2, kUserMessageEvent, <String, Object?>{'text': '三'}),
      ];

      final String text = renderer.render(events, turns: 2);

      expect(text, contains('二'));
      expect(text, contains('三'));
      expect(text.contains('你 › 一'), isFalse);
    });

    test('turns 超过实际轮数时全给', () {
      final String text = renderer.render(_oneTurn(), turns: 99);
      expect(text, contains('你 › 修一下 bug'));
    });

    test('无事件时给出明确说法', () {
      expect(renderer.render(const <SessionEvent>[]), contains('还没有'));
    });

    test('只有内部事件、没有可读内容时不返回空串', () {
      final String text = renderer.render(<SessionEvent>[
        _event(0, 'agent/round', <String, Object?>{'step': 0}),
      ]);
      expect(text.trim(), isNotEmpty);
    });

    test('工具结果只取首行，但报出总行数', () {
      // rg 命中 12 处和 1 处是不同的信息，砍到首行不能把条数也丢了。
      final String text = const TraceRenderer(toolResultChars: 40).render(
        <SessionEvent>[
          _event(0, kToolResultEvent, <String, Object?>{
            'name': 'rg',
            'content': List<String>.generate(12, (int i) => 'a.dart:$i')
                .join('\n'),
            'isError': false,
          }),
        ],
      );
      expect(text, contains('a.dart:0'));
      expect(text, contains('+11 行'));
      expect(text.contains('a.dart:5'), isFalse);
    });

    test('单行结果不追加行数后缀', () {
      final String text = renderer.render(<SessionEvent>[
        _event(0, kToolResultEvent, <String, Object?>{
          'name': 'rg',
          'content': '只有一行',
          'isError': false,
        }),
      ]);
      expect(text, contains('只有一行'));
      expect(text.contains('行）'), isFalse);
    });

    test('超长工具结果截断带省略号', () {
      final String text = const TraceRenderer(toolResultChars: 5).render(
        <SessionEvent>[
          _event(0, kToolResultEvent, <String, Object?>{
            'name': 'rg',
            'content': '很长的一行结果内容',
            'isError': false,
          }),
        ],
      );
      expect(text, endsWith('…'));
    });

    test('空内容显示（空）而不是留白', () {
      final String text = renderer.render(<SessionEvent>[
        _event(0, kToolResultEvent, <String, Object?>{
          'name': 'edit_file',
          'content': '',
          'isError': false,
        }),
      ]);
      expect(text, contains('（空）'));
    });

    test('压缩事件标出来', () {
      final String text = renderer.render(<SessionEvent>[
        _event(0, 'compaction/start'),
        _event(1, 'compaction/end', <String, Object?>{'error': 'summarize failed'}),
      ]);
      expect(text, contains('压缩开始'));
      expect(text, contains('✗ 压缩失败：summarize failed'));
    });

    test('工具结果缺 name 时跳过（不产生无名行）', () {
      final String text = renderer.render(<SessionEvent>[
        _event(0, kToolResultEvent, <String, Object?>{'content': 'x'}),
      ]);
      expect(text.trim(), isNotEmpty);
      expect(text.contains('›'), isFalse);
    });
  });
}
