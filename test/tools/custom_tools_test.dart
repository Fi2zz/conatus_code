/// 声明式自定义工具：CLI / HTTP 执行体、退出码、超时与注册。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

Directory _temp() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-tools-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

String _script(Directory dir, String body, {String name = 'tool.sh'}) {
  final File file = File('${dir.path}${Platform.pathSeparator}$name');
  file.writeAsStringSync('#!/bin/sh\n$body\n');
  Process.runSync('chmod', <String>['+x', file.path]);
  return file.path;
}

ToolContext _context(Map<String, Object?> arguments) => ToolContext(
  ToolCall(name: 'probe', arguments: arguments),
);

CustomTool _commandTool(String command, {int timeoutMs = 5000}) => CustomTool(
  config: CustomToolConfig(
    name: 'probe',
    description: 'probe',
    command: command,
    timeoutMs: timeoutMs,
  ),
  workdir: Directory.current.path,
);

void main() {
  test('CLI：JSON 参数走 stdin，content 走 stdout', () async {
    final Directory dir = _temp();
    final String command = _script(
      dir,
      'input=\$(cat)\nprintf \'{"content":"ok:%s"}\' "\$input"',
    );

    final ToolResult result = await _commandTool(command).call(
      _context(<String, Object?>{'word': 'hi'}),
    );

    expect(result.isError, isFalse);
    expect(result.content, contains('ok:'));
    expect(result.content, contains('"word":"hi"'));
  });

  test('CLI：非零退出码 → TOOL_EXIT，带 stderr', () async {
    final Directory dir = _temp();
    final String command = _script(dir, 'echo boom >&2\nexit 3');

    final ToolResult result = await _commandTool(command).call(_context({}));

    expect(result.isError, isTrue);
    expect(result.error!.code, 'TOOL_EXIT');
    expect(result.content, contains('boom'));
  });

  test('CLI：超时 → TOOL_TIMEOUT', () async {
    final Directory dir = _temp();
    final String command = _script(dir, 'sleep 2');

    final ToolResult result = await _commandTool(
      command,
      timeoutMs: 100,
    ).call(_context({}));

    expect(result.isError, isTrue);
    expect(result.error!.code, 'TOOL_TIMEOUT');
  });

  test('CLI：结构化 error 与纯文本输出', () async {
    final Directory dir = _temp();
    final String errorCommand = _script(
      dir,
      'printf \'{"error":{"code":"NOPE","message":"bad input"}}\'',
      name: 'error.sh',
    );
    final String textCommand = _script(
      dir,
      'printf hello',
      name: 'text.sh',
    );

    final ToolResult error = await _commandTool(errorCommand).call(_context({}));
    final ToolResult text = await _commandTool(textCommand).call(_context({}));

    expect(error.isError, isTrue);
    expect(error.error!.code, 'NOPE');
    expect(text.isError, isFalse);
    expect(text.content, 'hello');
  });

  test('HTTP：JSON body 与 content 响应', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(server.close);
    String? received;
    server.listen((HttpRequest request) async {
      received = await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write('{"content":"http-ok"}');
      await request.response.close();
    });

    final CustomTool tool = CustomTool(
      config: CustomToolConfig(
        name: 'probe',
        description: 'probe',
        url: 'http://127.0.0.1:${server.port}/probe',
      ),
      workdir: Directory.current.path,
    );

    final ToolResult result = await tool.call(
      _context(<String, Object?>{'q': 'x'}),
    );

    expect(result.isError, isFalse);
    expect(result.content, 'http-ok');
    expect(received, contains('"q":"x"'));
  });

  test('HTTP：非 2xx → TOOL_HTTP', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(server.close);
    server.listen((HttpRequest request) async {
      request.response.statusCode = 503;
      request.response.write('down');
      await request.response.close();
    });

    final CustomTool tool = CustomTool(
      config: CustomToolConfig(
        name: 'probe',
        description: 'probe',
        url: 'http://127.0.0.1:${server.port}/probe',
      ),
      workdir: Directory.current.path,
    );

    final ToolResult result = await tool.call(_context({}));

    expect(result.isError, isTrue);
    expect(result.error!.code, 'TOOL_HTTP');
    expect(result.content, contains('503'));
  });

  test('provideCustomTools 把工具注册进上下文', () {
    final Context app = Context.root(name: 'custom-tools');
    addTearDown(app.dispose);
    provideTools(app);

    provideCustomTools(
      app,
      tools: const <CustomToolConfig>[
        CustomToolConfig(
          name: 'probe',
          description: 'probe',
          command: 'true',
        ),
      ],
      workdir: Directory.current.path,
    );

    expect(app.tools.names, contains('probe'));
    expect(app.tools.names, contains('probe'));
  });
}
