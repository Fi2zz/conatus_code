/// 装配期回归：这两条都曾因「测试绕开真实装配」而长期漏网。
///
/// - 大工具结果：溢出目录曾落在 `systemTemp`，而 fs jail 默认以工作目录为根，
///   于是 >80KB 的结果直接 `FS_SANDBOX_DENIED`；就算写出去，模型按预览里的提示
///   `read_file` 读回来也会被拒。
/// - 换模型：装配期无条件 `provide('llmChain', …)`，换模型再 provide 一次撞
///   Context 的服务键唯一性 → 第一次切换必抛 StateError。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/providers.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _Stub implements LlmProvider {
  @override
  String get name => 'stub';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async =>
      const LlmResult(content: 'ok', provider: 'stub', model: 'stub');

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

/// 按 `bin/conatus_code.dart` 的真实接线装配：fs jail 到工作目录，`fs_jail` 默认为开。
Future<ConatusTuiRuntime> _boot(
  Directory dir, {
  List<ModelConfig> models = const <ModelConfig>[],
}) async {
  final String sep = Platform.pathSeparator;
  File('${dir.path}${sep}pubspec.yaml').writeAsStringSync('name: x\n');
  final ConatusTuiRuntime rt = await ConatusTuiRuntime.create(
    baseDir: dir.path,
    sessionDir: dir.path,
    memoryFile: '${dir.path}${sep}memory.json',
    workdir: dir.path,
    // 与 bin 一致：Layer 1 的 jail 是在 bin 里做好再传进来的。
    fs: JailedFileSystem(root: dir.resolveSymbolicLinksSync()),
    webTools: false,
    skills: false,
    llm: FallbackLlm(<LlmProvider>[_Stub()]),
    providers: <ProviderConfig>[
      const ProviderConfig(
          name: 'mock',
          baseUrl: 'https://example.invalid/v1',
          apiKey: 'sk-test', // 无 key 时 buildLlmChain 正确地返回 null
        ),
    ],
    models: models,
    provider: 'mock',
    // chainEntries 靠 model 拼出 'provider/model'；不给 model 则建不出链。
    model: models.isEmpty ? null : 'm1',
  );
  addTearDown(rt.dispose);
  return rt;
}

void main() {
  test('大工具结果：溢出文件写在 jail 内，且模型能 read_file 读回来', () async {
    final Directory dir = Directory.systemTemp.createTempSync('nava-spill');
    addTearDown(() => dir.deleteSync(recursive: true));
    final Context app = (await _boot(dir)).app;

    // 走注册表以命中驱逐中间件（阈值 80_000）。
    app.effect(() => app.tools.fn(
          'big_tool',
          handler: (ToolContext ctx) async => ToolResult.success('y' * 85000),
        ));
    final ToolResult first =
        await app.tools.call(const ToolCall(name: 'big_tool'));

    expect(first.isError, isFalse, reason: '大结果不应因沙箱而失败');
    // 路径以 '/' 起头：中文没有空格，用 \S+ 会把「完整内容已写入文件：」整句吞进去。
    final RegExpMatch? spill = RegExp(r'(/\S+\.txt)').firstMatch(first.content);
    expect(spill, isNotNull, reason: '预览应给出溢出文件路径，实际：${first.content}');

    // 关键：预览让模型 read_file 读回来，这一步以前必然被 jail 拒绝。
    final ToolResult read = await app.tools.call(ToolCall(
      name: 'read_file',
      arguments: <String, Object?>{'path': spill!.group(1)},
    ));
    expect(read.isError, isFalse, reason: '溢出文件必须可被 read_file 读回');
    expect(read.content, contains('yyyy'));
  });

  test('换模型：槽位可反复替换，不触发服务键唯一性报错', () async {
    final Directory dir = Directory.systemTemp.createTempSync('nava-swap');
    addTearDown(() => dir.deleteSync(recursive: true));
    final Context app = (await _boot(dir, models: <ModelConfig>[
      const ModelConfig(provider: 'mock', model: 'm1'),
    ])).app;

    // 旧实现在这里抛：Bad state: 服务 "llmChain" 已在上下文 "conatus" 中提供。
    expect(app.has('llmChainSlot'), isTrue);
    final LlmChainSlot slot = app.require<LlmChainSlot>('llmChainSlot');
    expect(() => slot.current = null, returnsNormally);
    // 槽位是同一个实例：换模型只改内容，不会顶掉服务键。
    expect(app.require<LlmChainSlot>('llmChainSlot'), same(slot));
  });

  test('doctor 从槽位读当前链', () async {
    final Directory dir = Directory.systemTemp.createTempSync('nava-doc');
    addTearDown(() => dir.deleteSync(recursive: true));
    final Context app = (await _boot(dir, models: <ModelConfig>[
      const ModelConfig(provider: 'mock', model: 'm1'),
    ])).app;

    final DoctorCheck chain = doctorChecks(app)
        .firstWhere((DoctorCheck c) => c.name == '模型回退链');
    expect(chain.ok, isTrue, reason: '装配后应能报出回退链');
  });
}
