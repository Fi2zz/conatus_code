/// `dart analyze --format=machine` 解析与渲染的纯函数测试。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

const String kRoot = '/repo';
const String kLibA = '/repo/lib/a.dart';

DartDiagnostic _one({
  String severity = 'ERROR',
  String code = 'C',
  String path = kLibA,
  int line = 1,
  int column = 1,
  String message = 'msg',
}) =>
    DartDiagnostic(
      severity: severity,
      code: code,
      path: path,
      line: line,
      column: column,
      message: message,
    );

void main() {
  group('parseDartMachine', () {
    test('解析定长字段：严重级/码/路径/行列/消息', () {
      final List<DartDiagnostic> items = parseDartMachine(
        'ERROR|COMPILE_TIME_ERROR|RETURN_OF_INVALID_TYPE|/repo/lib/a.dart'
        '|12|15|2|返回值类型不对',
      );
      expect(items, hasLength(1));
      expect(items.single.severity, 'ERROR');
      expect(items.single.isError, isTrue);
      expect(items.single.code, 'RETURN_OF_INVALID_TYPE');
      expect(items.single.path, kLibA);
      expect(items.single.line, 12);
      expect(items.single.column, 15);
      expect(items.single.message, '返回值类型不对');
    });

    test('消息里含 | 时用 | 连接还原（不是简单取第 8 段）', () {
      final List<DartDiagnostic> items = parseDartMachine(
        'INFO|HINT|X|/repo/lib/a.dart|1|1|1|a | b | c',
      );
      expect(items.single.message, 'a | b | c');
    });

    test('多行消息各自成条', () {
      final List<DartDiagnostic> items = parseDartMachine(
        'WARNING|W|U|/repo/lib/a.dart|3|8|2|第一行\n'
        'ERROR|E|V|/repo/lib/a.dart|9|2|2|第二行',
      );
      expect(items, hasLength(2));
      expect(items[0].severity, 'WARNING');
      expect(items[1].severity, 'ERROR');
    });

    test('字段不足 / 行列非数字 / 空行一律丢弃', () {
      final List<DartDiagnostic> items = parseDartMachine(
        'Directory or file doesn\'t exist: lib/a.dart\n'
        '\n'
        'Usage: dart analyze [arguments] [<directory>]\n'
        'ERROR|T|C|/repo/lib/a.dart|x|1|2|列号坏了\n'
        'ERROR|T|C|/repo/lib/a.dart|1|y|2|行号坏了\n',
      );
      expect(items, isEmpty);
    });
  });

  group('formatDartDiagnostics', () {
    test('空输入返回空串', () {
      expect(formatDartDiagnostics(<DartDiagnostic>[], workdir: kRoot), '');
    });

    test('绝对路径压成相对工作目录的短路径', () {
      final String text = formatDartDiagnostics(<DartDiagnostic>[_one()],
          workdir: kRoot);
      expect(text, contains('lib/a.dart'));
      expect(text, isNot(contains('/repo/')));
    });

    test('不在工作目录下的路径原样保留', () {
      final String text = formatDartDiagnostics(
        <DartDiagnostic>[_one(path: '/elsewhere/z.dart')],
        workdir: kRoot,
      );
      expect(text, contains('/elsewhere/z.dart'));
    });

    test('按文件分组，组内错误在前', () {
      final String text = formatDartDiagnostics(<DartDiagnostic>[
        _one(severity: 'WARNING', code: 'W', line: 9),
        _one(code: 'E', line: 2),
        _one(path: '/repo/lib/b.dart', code: 'B', line: 2),
      ], workdir: kRoot);
      expect(text, contains('lib/a.dart'));
      expect(text, contains('lib/b.dart'));
      expect(text.indexOf('E'), lessThan(text.indexOf('W')));
    });

    test('同文件超过上限时计数剩余条数', () {
      final String text = formatDartDiagnostics(
        List<DartDiagnostic>.generate(
            15, (int i) => _one(line: i, code: 'C$i')),
        workdir: kRoot,
        maxPerFile: 4,
      );
      expect('C0'.allMatches(text), hasLength(1));
      expect(text, isNot(contains('C4')));
      expect(text, contains('另有 11 条未显示'));
    });
  });
}
