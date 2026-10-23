/// 工具后置中间件：读过路径后把沿途 AGENTS.md 记入指令层。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

final String _sep = Platform.pathSeparator;

void _write(String base, List<String> parts, String content) {
  final String path = <String>[base, ...parts].join(_sep);
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

void main() {
  late Directory dir;
  late Context app;
  late InstructionLoader loader;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nava-notes-');
    File('${dir.path}${_sep}AGENTS.md').writeAsStringSync('ROOT');
    app = Context.root(name: 'instructions');
    provideTools(app);
    loader = provideInstructionLoader(
      app,
      workdir: dir.path,
      home: '${dir.path}${_sep}home',
    );
    final Disposer disposer = instrumentInstructionNotes(app, loader);
    app.effect(() => disposer);
  });

  tearDown(() {
    app.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  void registerTool(String name) {
    app.tools.fn(
      name,
      params: <ParamSpec>[ParamSpec.string('path')],
      handler: (ToolContext context) async => ToolResult.success('ok'),
    );
  }

  test('markdown 路径 tools 均记下嵌套 AGENTS.md，下一次 compose 可见', () async {
    final List<String> tools = <String>[
      'read_file',
      'list_files',
      'rg',
      'glob',
    ];
    for (int i = 0; i < tools.length; i++) {
      registerTool(tools[i]);
      final String nested = <String>[dir.path, 'pkg$i', 'sub'].join(_sep);
      _write(nested, <String>['AGENTS.md'], 'NESTED-$i');
      _write(nested, <String>['file.dart'], 'x');

      final ToolResult result = await app.tools.call(
        ToolCall(
          name: tools[i],
          arguments: <String, Object?>{'path': '$nested${_sep}file.dart'},
        ),
      );

      expect(result.isError, isFalse);
      expect(await loader.compose(), contains('NESTED-$i'));
    }
  });

  test('未列出的工具与无 path 参数不触发', () async {
    registerTool('echo');
    app.tools.fn('read_file', handler: (_) async => ToolResult.success('ok'));

    await app.tools.call(
      const ToolCall(name: 'echo', arguments: <String, Object?>{'path': 'x'}),
    );
    await app.tools.call(const ToolCall(name: 'read_file'));

    expect(await loader.compose(), contains('ROOT'));
    expect(await loader.compose(), isNot(contains('NESTED')));
  });
}
