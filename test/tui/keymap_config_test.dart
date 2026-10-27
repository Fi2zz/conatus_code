/// `[keybinds]` 配置解析、首次启动模板与 `/keybinds` 输出。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _NoopProvider implements LlmProvider {
  @override
  String get name => 'noop';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) => throw UnimplementedError();

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) => const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

String _writeToml(String content) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-keymap-cfg');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File(
    '${dir.path}${Platform.pathSeparator}$kConfigFileName',
  );
  file.writeAsStringSync(content);
  return file.path;
}

void main() {
  test('[keybinds] 解析：引号动作 ID、嵌套点号与 false 关闭', () {
    final ConatusCodeConfig config = loadConfig(
      path: _writeToml('''
[keybinds]
leader = "ctrl+space"
"app.clear" = "f2"
session.new = "<leader>n"
"theme.switch" = false
'''),
    );
    expect(config.keybinds['leader'], 'ctrl+space');
    expect(config.keybinds['app.clear'], 'f2');
    expect(config.keybinds['session.new'], '<leader>n');
    expect(config.keybinds['theme.switch'], 'none');
  });

  test('首次启动模板包含 [keybinds] 示例', () {
    final Directory dir = Directory.systemTemp.createTempSync('nava-key-tpl');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String path = '${dir.path}${Platform.pathSeparator}$kConfigFileName';
    loadConfig(path: path);
    final String template = File(path).readAsStringSync();
    expect(template, contains('# [keybinds]'));
    expect(template, contains('leader = "ctrl+x"'));
    expect(template, contains('<leader>n'));
  });

  test('renderKeybinds 列出当前绑定、冲突与局部按键边界', () {
    final Keymap keymap = Keymap.fromConfig(<String, String>{
      'app.clear': 'f2',
      'help.show': 'f2',
    });
    final String text = renderKeybinds(keymap);
    expect(text, contains('app.exit'));
    expect(text, contains('ctrl+c, ctrl+d'));
    expect(text, contains('session.new'));
    expect(text, contains('ctrl+x 再 n'));
    expect(text, contains('键位冲突'));
    expect(text, contains('视图内按键'));
  });

  test('/keybinds 把绑定打印到屏上', () async {
    final Context app = Context.root();
    addTearDown(app.dispose);
    provideTools(app);
    provideLlm(app, llm: FallbackLlm(<LlmProvider>[_NoopProvider()]));
    final SessionStore sessions = provideSessions(app);
    final ConatusTuiController controller = ConatusTuiController(
      app: app,
      sessions: sessions,
      name: '测试',
      initialSession: 'keymap',
      modelLabel: 'mock',
      onExit: () {},
    );
    await controller.handleLine('/keybinds');
    final String output = controller.transcript.messages.last.text;
    expect(output, contains('app.exit'));
    expect(output, contains('ctrl+c, ctrl+d'));
    controller.dispose();
  });
}
