/// 全链路快照：跑完一轮真实 headless 会话（模型发起写/编辑）后，项目
/// `.opencode/**` 的字节必须与开跑前完全一致；checkpoint 也默认忽略它。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/src/checkpoint_config_adapter.dart';
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

/// 记录 `.opencode` 整树的内容 + 元数据：路径 → 字节 / mtime / 权限位。
///
/// 只读承诺不止「字节没变」：遍历、读取、检查点扫描都不该改 mtime 或权限位。
Map<String, String> _stats(String root) {
  final Directory dir = Directory(root);
  if (!dir.existsSync()) return <String, String>{};
  final Map<String, String> out = <String, String>{};
  for (final FileSystemEntity entity in dir.listSync(
    recursive: true,
    followLinks: false,
  )) {
    final FileStat stat = FileStat.statSync(entity.path);
    out[entity.path] =
        '${stat.modified.millisecondsSinceEpoch}:'
        '${stat.mode & 0xFFF}';
  }
  return out;
}

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this._replies);

  final List<LlmResult> _replies;

  /// 每次模型调用收到的完整消息（含 tool 结果），供断言错误透传。
  final List<List<LlmMessage>> calls = <List<LlmMessage>>[];
  int _index = 0;

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    // 反思调用（`provideReflection` 的 onError 策略）也走同一 provider：
    // 直接回「继续」，不消耗脚本回复，保证会话步数与脚本一一对应。
    if (messages.length == 1 && messages.single.content.contains('任务执行监督者')) {
      return const LlmResult(
        content: '{"decision":"continue","reason":"只读约束"}',
        provider: 's',
        model: 'm',
      );
    }
    calls.add(messages);
    return _replies[_index++];
  }

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
/// 能落盘），最后收口。返回结果与模型实际收到的消息（含 tool 错误）。
Future<(HeadlessResult, List<List<LlmMessage>>)> _runSessionWithEdits(
  String workdir,
  String baseDir,
) async {
  final String sep = Platform.pathSeparator;
  final _ScriptedProvider provider = _ScriptedProvider(<LlmResult>[
    _tool(
      'c1',
      'write',
      '{"path":".opencode/commands/x.md","content":"pwned"}',
    ),
    _tool(
      'c2',
      'edit',
      '{"path":".opencode/agents/a.md","old_string":"agent","new_string":"pwned"}',
    ),
    _tool('c3', 'write', '{"path":"notes.txt","content":"hello"}'),
    const LlmResult(content: '完成', provider: 's', model: 'm'),
  ]);
  final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
    baseDir: baseDir,
    sessionDir: '$baseDir$sep/sessions',
    memoryFile: '$baseDir$sep/memory.json',
    workdir: workdir,
    webTools: false,
    skills: false,
    interactive: false,
    fs: LocalFileSystem(cwd: workdir),
    llm: FallbackLlm(<LlmProvider>[provider]),
  );
  addTearDown(runtime.dispose);
  // 装配确实把闸门包在 fs 接缝上（工具都从这里取 fs）。
  expect(runtime.app.require<FileSystem>('fs'), isA<ReadOnlyPathGuard>());
  final HeadlessResult result = await runHeadless(runtime, prompt: '改文件');
  return (result, provider.calls);
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
    final Map<String, String> beforeStats = _stats('${dir.path}/.opencode');

    final (HeadlessResult result, List<List<LlmMessage>> calls) =
        await _runSessionWithEdits(dir.path, base.path);

    expect(result.exitCode, 0);
    expect(_snapshot('${dir.path}/.opencode'), before);
    expect(
      _stats('${dir.path}/.opencode'),
      beforeStats,
      reason: '只读目录的 mtime / 权限位也不能被改动',
    );
    // 两次 `.opencode` 写入都被拒绝，且拒绝原因是 READ_ONLY_PATH（不是
    // 「文件已存在」等其它错误）。
    final Iterable<LlmMessage> toolMessages = calls.last.where(
      (LlmMessage m) => m.role == 'tool',
    );
    expect(
      toolMessages
          .where((LlmMessage m) => m.content.contains('READ_ONLY_PATH'))
          .length,
      2,
    );
    // 会话本身确实执行了写入：普通文件落了盘，闸门不是「整个 fs 全拒」。
    expect(File('${dir.path}/notes.txt').readAsStringSync(), 'hello');
  });

  test('checkpoint 产品策略忽略 .opencode（rewind 不写回）', () {
    final CheckpointPolicy policy = checkpointOptions(
      const CheckpointConfig(),
    ).policy;
    expect(policy.readOnlyPrefixes, contains('.opencode'));
    expect(
      checkpointExcluded(
        '.opencode${Platform.pathSeparator}commands${Platform.pathSeparator}x.md',
        'other',
        policy,
      ),
      isTrue,
    );
  });
}
