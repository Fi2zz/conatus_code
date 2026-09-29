/// `/export`：会话导出为 markdown。
library;

import 'dart:io';

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

Session _session() => Session(id: 'session_abc123', seed: <SessionEvent>[
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
      }),
    ]);

SessionExport _export({double cost = 0, String rate = ''}) => SessionExport(
      session: _session(),
      modelLabel: 'testprov/m1',
      workdir: '/repo/demo',
      cost: cost,
      promptTokens: 1200,
      completionTokens: 340,
      rateSummary: rate,
    );

void main() {
  group('markdown 渲染', () {
    test('带会话头：id / 模型 / 工作目录 / 事件数', () {
      final String md = _export().toMarkdown();

      expect(md, startsWith('# nava 会话 session_abc123'));
      expect(md, contains('- 会话：`session_abc123`'));
      expect(md, contains('- 模型：testprov/m1'));
      expect(md, contains('- 工作目录：`/repo/demo`'));
      expect(md, contains('- 事件：5 条'));
    });

    test('有 token / 成本时带上费率来源', () {
      final String md = _export(cost: 0.42, rate: '\$1/M in').toMarkdown();

      expect(md, contains('- token：输入 1200 / 输出 340'));
      expect(md, contains('- 费率：\$1/M in'));
      expect(md, contains(r'成本：$0.4200'));
      expect(md, contains('非账单'), reason: '要讲清这不是账单数字');
    });

    test('无成本时不出成本行', () {
      final String md = _export().toMarkdown();
      expect(md.contains('成本：'), isFalse);
    });

    test('思考折叠进 details，正文独立成节', () {
      final String md = _export().toMarkdown();

      expect(md, contains('<details><summary>思考</summary>'));
      expect(md, contains('先看文件'));
      expect(md, contains('## 助手'));
      expect(md, contains('改完了'));
    });

    test('工具结果带成败标记', () {
      final String md = _export().toMarkdown();

      expect(md, contains('### ✓ read_file'));
      expect(md, contains('### ✗ edit_file'));
      expect(md, contains('boom: permission denied'));
    });

    // 导出本该完整；只有病态输出才截断，且要说明丢了多少。
    test('工具结果默认不截断', () {
      final String big = List<String>.filled(300, '一行内容').join('\n');
      final SessionExport export = SessionExport(
        session: Session(id: 's', seed: <SessionEvent>[
          _event(0, kToolResultEvent, <String, Object?>{
            'name': 'rg',
            'content': big,
            'isError': false,
          }),
        ]),
        modelLabel: 'm',
      );
      expect(export.toMarkdown().contains('一行内容'), isTrue);
    });

    test('超上限截断并说明丢了多少', () {
      final String huge = 'x' * (kExportMaxToolChars + 500);
      final SessionExport export = SessionExport(
        session: Session(id: 's', seed: <SessionEvent>[
          _event(0, kToolResultEvent, <String, Object?>{
            'name': 'rg',
            'content': huge,
            'isError': false,
          }),
        ]),
        modelLabel: 'm',
      );
      final String md = export.toMarkdown();

      expect(md, contains('已截断'));
      expect(md, contains('共 ${huge.length} 字符'),
          reason: '静默截断会让人以为那就是全部');
    });

    test('内部事件不进导出', () {
      final SessionExport export = SessionExport(
        session: Session(id: 's', seed: <SessionEvent>[
          _event(0, kUserMessageEvent, <String, Object?>{'text': 'x'}),
          _event(1, 'agent/round', <String, Object?>{'step': 0}),
          _event(2, 'plan/updated', <String, Object?>{'plan': '[]'}),
        ]),
        modelLabel: 'm',
      );
      final String md = export.toMarkdown();

      expect(md.contains('agent/round'), isFalse);
      expect(md.contains('plan/updated'), isFalse);
    });

    test('压缩事件留痕，压缩失败显式提示', () {
      final SessionExport export = SessionExport(
        session: Session(id: 's', seed: <SessionEvent>[
          _event(0, 'compaction/start'),
          _event(1, 'compaction/end', <String, Object?>{'error': 'summarize 失败'}),
        ]),
        modelLabel: 'm',
      );
      final String md = export.toMarkdown();

      expect(md, contains('早期历史已折叠成摘要'));
      expect(md, contains('压缩失败'));
    });

    test('缺省文件名去掉 session_ 前缀', () {
      expect(_export().defaultFileName, 'nava-abc123.md');
    });
  });

  group('落点解析', () {
    test('缺省落项目数据目录的 exports/', () {
      expect(
        resolveExportPath(
          projectDataDir: '/data/proj',
          fileName: 'nava-1.md',
        ),
        '${Platform.pathSeparator}data${Platform.pathSeparator}proj'
            '${Platform.pathSeparator}exports${Platform.pathSeparator}nava-1.md',
      );
    });

    test('给绝对路径就照写', () {
      expect(
        resolveExportPath(
          target: '/tmp/out.md',
          projectDataDir: '/data',
          fileName: 'nava-1.md',
        ),
        '/tmp/out.md',
      );
    });

    test('~ 展开', () {
      expect(
        resolveExportPath(
          target: '~/notes/out.md',
          projectDataDir: '/data',
          fileName: 'nava-1.md',
          env: <String, String>{'HOME': '/home/me'},
        ),
        '${Platform.pathSeparator}home${Platform.pathSeparator}me'
            '${Platform.pathSeparator}notes${Platform.pathSeparator}out.md',
      );
    });

    test('以分隔符结尾视为目录，补上文件名', () {
      expect(
        resolveExportPath(
          target: '/tmp/dir/',
          projectDataDir: '/data',
          fileName: 'nava-1.md',
        ),
        '${Platform.pathSeparator}tmp${Platform.pathSeparator}dir'
            '${Platform.pathSeparator}nava-1.md',
      );
    });

    test('空串 / 纯空白按缺省处理', () {
      for (final String blank in <String>['', '   ']) {
        expect(
          resolveExportPath(
            target: blank,
            projectDataDir: '/data',
            fileName: 'n.md',
          ),
          contains('exports'),
        );
      }
    });
  });

  group('落盘', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('nava-export');
      addTearDown(() => dir.deleteSync(recursive: true));
    });

    test('写出文件并返回绝对路径', () async {
      final String path = await _export().write(
        projectDataDir: dir.path,
      );

      expect(File(path).existsSync(), isTrue);
      expect(File(path).readAsStringSync(), contains('改完了'));
    });

    // 缺省落点是 <projectDataDir>/exports/。真实运行里 projectDataDir 由
    // resolveProjectDataDir 解析成 ~/.nava/projects/<编码工作区>（那条不变量由
    // project_data_dir_test 守），所以导出不会落进用户的代码仓库。
    test('缺省落点是 <projectDataDir>/exports/', () async {
      final String path = await _export().write(projectDataDir: dir.path);

      expect(
        path,
        '${dir.absolute.path}${Platform.pathSeparator}exports'
        '${Platform.pathSeparator}nava-abc123.md',
      );
      expect(File(path).existsSync(), isTrue);
    });

    test('父目录不存在时自动创建', () async {
      final String nested = '${dir.path}${Platform.pathSeparator}a'
          '${Platform.pathSeparator}b${Platform.pathSeparator}c.md';
      await _export().write(target: nested, projectDataDir: dir.path);

      expect(File(nested).existsSync(), isTrue);
    });

    test('重复导出会覆盖而不是报错', () async {
      final String first = await _export().write(projectDataDir: dir.path);
      final String second = await _export().write(projectDataDir: dir.path);

      expect(second, first);
      expect(File(first).existsSync(), isTrue);
    });
  });
}
