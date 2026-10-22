/// 全链路快照：跑完一轮真实 headless 会话（模型发起写/编辑）后，项目
/// `.opencode/**` 的字节必须与开跑前完全一致；checkpoint 也默认忽略它。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/fs_tools.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

/// 记录 `.opencode` 整树内容：文件路径 → 字节（链接记为 `-> 目标`）。
Map<String, String> _snapshot(String root) {
  final Directory dir = Directory(root);
  if (!dir.existsSync()) return <String, String>{};
  final Map<String, String> out = <String, String>{};
  for (final FileSystemEntity entity in dir.listSync(
    recursive: true,
    followLinks: false,
  )) {
    final String rel = entity.path.substring(root.length);
    if (entity is Link) {
      out[rel] = '-> ${entity.targetSync()}';
    } else if (entity is File) {
      out[rel] = entity.readAsBytesSync().join(',');
    }
  }
  return out;
}

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this._replies);

  final List<LlmResult> _replies;
  int _index = 0;

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async => _replies[_index++];

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) => const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

LlmResult _tool(String id, String name, String args) => LlmResult(
  content: '',
  provider: 's',
  model: 'm',
  toolCalls: <LlmToolCall>[LlmToolCall(id: id, name: name, arguments: args)],
);

/// 一轮 headless 会话：先试图写 `.opencode/**`，再写普通文件（证明会话本身
/// 能落盘），最后收口。返回运行时供调用方断言。
Future<HeadlessResult> _runSessionWithEdits(
  String workdir,
  String baseDir,
) async {
  final String sep = Platform.pathSeparator;
  final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
    baseDir: baseDir,
    sessionDir: '$baseDir$sep/sessions',
    memoryFile: '$baseDir$sep/memory.json',
    workdir: workdir,
    webTools: false,
    skills: false,
    interactive: false,
    fs: LocalFileSystem(cwd: workdir),
    llm: FallbackLlm(<LlmProvider>[
      _ScriptedProvider(<LlmResult>[
        _tool(
          'c1',
          'write_file',
          '{"path":".opencode/commands/x.md","content":"pwned"}',
        ),
        _tool(
          'c2',
          'edit_file',
          '{"path":".opencode/agents/a.md","old_string":"agent","new_string":"pwned"}',
        ),
        _tool('c3', 'write_file', '{"path":"notes.txt","content":"hello"}'),
        const LlmResult(content: '完成', provider: 's', model: 'm'),
      ]),
    ]),
  );
  addTearDown(runtime.dispose);
  // 装配确实把闸门包在 fs 接缝上（工具都从这里取 fs）。
  expect(runtime.app.require<FileSystem>('fs'), isA<ReadOnlyPathGuard>());
  return runHeadless(runtime, prompt: '改文件');
}

void main() {
  test('full session leaves .opencode bytes unchanged', () async {
    final Directory dir = Directory.systemTemp.createTempSync('nava-oc-work-');
    final Directory base = Directory.systemTemp.createTempSync('nava-oc-base-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      if (base.existsSync()) base.deleteSync(recursive: true);
    });
    Directory('${dir.path}/.opencode/commands').createSync(recursive: true);
    Directory('${dir.path}/.opencode/agents').createSync(recursive: true);
    File('${dir.path}/.opencode/commands/x.md').writeAsStringSync('before');
    File('${dir.path}/.opencode/agents/a.md').writeAsStringSync('agent');
    final Map<String, String> before = _snapshot('${dir.path}/.opencode');

    final HeadlessResult result = await _runSessionWithEdits(
      dir.path,
      base.path,
    );

    expect(result.exitCode, 0);
    expect(_snapshot('${dir.path}/.opencode'), before);
    // 会话本身确实执行了写入：普通文件落了盘，闸门不是「整个 fs 全拒」。
    expect(File('${dir.path}/notes.txt').readAsStringSync(), 'hello');
  });

  test('checkpoint 默认忽略 .opencode（rewind 不写回）', () {
    expect(kCheckpointDefaultIgnores, contains('.opencode'));
    expect(
      checkpointExcluded(
        '.opencode${Platform.pathSeparator}commands${Platform.pathSeparator}x.md',
        'other',
        const <String>[],
      ),
      isTrue,
    );
  });
}
