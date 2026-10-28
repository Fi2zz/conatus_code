/// LSP 运行时接入与 /lsp 命令。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

Directory _tempDir() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-lsp-runtime');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

LspConfig _config(String marker) => LspConfig(
      enabled: true,
      servers: <LspServerConfig>[
        LspServerConfig(
          name: 'fake',
          command: <String>[
            Platform.resolvedExecutable,
            '${Directory.current.path}/test/lsp/fixtures/fake_lsp_server.dart',
            '--marker',
            marker,
          ],
          extensions: const <String>['.dart'],
        ),
      ],
    );

Future<ConatusTuiRuntime> _runtime(Directory dir, LspConfig lsp) {
  return ConatusTuiRuntime.create(
    baseDir: dir.path,
    sessionDir: '${dir.path}/sessions',
    memoryFile: '${dir.path}/memory.json',
    webTools: false,
    skills: false,
    llm: FallbackLlm(const <LlmProvider>[]),
    lsp: lsp,
    interactive: false,
  );
}

void main() {
  test('未启用 LSP 时不注册服务与工具', () async {
    final Directory dir = _tempDir();
    final ConatusTuiRuntime runtime = await _runtime(
      dir,
      const LspConfig(),
    );
    try {
      expect(runtime.lspManager, isNull);
      expect(runtime.tools.names, isNot(contains('lsp_diagnostics')));
    } finally {
      await runtime.dispose();
    }
  });

  test('启用 LSP 时注册服务、工具并支持 /lsp', () async {
    final Directory dir = _tempDir();
    final String marker = '${dir.path}/starts';
    final ConatusTuiRuntime runtime = await _runtime(dir, _config(marker));
    try {
      expect(runtime.lspManager, isNotNull);
      expect(
        runtime.tools.names,
        containsAll(<String>[
          'lsp_diagnostics',
          'lsp_hover',
          'lsp_definition',
          'lsp_references',
          'lsp_document_symbols',
        ]),
      );
      final File file = File('${dir.path}/a.dart')..writeAsStringSync('a');
      final ToolResult diagnostics = await runtime.tools.call(
        ToolCall(name: 'lsp_diagnostics', arguments: <String, Object?>{'path': file.path}),
      );
      expect(diagnostics.content, contains('fake diagnostic'));
      final ToolResult hover = await runtime.tools.call(
        ToolCall(
          name: 'lsp_hover',
          arguments: <String, Object?>{
            'path': file.path,
            'line': 1,
            'column': 1,
          },
        ),
      );
      expect(hover.content, contains('fake hover'));
      final ToolResult edit = await runtime.tools.call(
        ToolCall(
          name: 'write_file',
          arguments: <String, Object?>{
            'path': file.path,
            'content': 'void main() {}',
            'mode': 'overwrite',
          },
        ),
      );
      expect(edit.content, contains('fake diagnostic'));
      final ConatusTuiController controller = runtime.createController(
        onExit: () {},
      );
      await controller.start();
      await controller.handleLine('/lsp');
      final String text = controller.transcript.messages.last.text;
      expect(text, contains('fake'));
      expect(text, contains('running'));
      expect(text, contains('hover'));
      controller.dispose();
    } finally {
      await runtime.dispose();
    }
  });

  test('/lsp 显示运行状态，restart 回到 idle', () async {
    final Directory dir = _tempDir();
    final String marker = '${dir.path}/starts';
    final File file = File('${dir.path}/a.dart')..writeAsStringSync('a');
    final ConatusTuiRuntime runtime = await _runtime(dir, _config(marker));
    try {
      await runtime.lspManager!.diagnose(file.path);
      final ConatusTuiController controller = runtime.createController(
        onExit: () {},
      );
      await controller.start();

      await controller.handleLine('/lsp');
      expect(controller.transcript.messages.last.text, contains('running'));

      await controller.handleLine('/lsp restart');
      expect(controller.transcript.messages.last.text, contains('已重启'));
      await controller.handleLine('/lsp');
      expect(controller.transcript.messages.last.text, contains('idle'));
      controller.dispose();
    } finally {
      await runtime.dispose();
    }
  });
}
