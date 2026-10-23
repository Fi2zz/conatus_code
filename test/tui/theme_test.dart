/// 主题 token 层与 `/theme`：默认色不变、未知主题回落、浮层渲染与切换生效。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

/// 从不被调用的占位 provider。
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

ConatusTuiController _controller(String session) {
  final Context app = Context.root();
  addTearDown(app.dispose);
  provideTools(app);
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[_NoopProvider()]));
  final SessionStore sessions = provideSessions(app);
  return ConatusTuiController(
    app: app,
    sessions: sessions,
    name: '测试',
    initialSession: session,
    modelLabel: 'mock',
    onExit: () {},
  );
}

String _writeToml(String content) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-theme-cfg');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File(
    '${dir.path}${Platform.pathSeparator}$kConfigFileName',
  );
  file.writeAsStringSync(content);
  return file.path;
}

void main() {
  setUp(() => NavaTheme.use('default'));

  test('default palette preserves current colors', () {
    NavaTheme.use('default');
    final NavaPalette palette = NavaTheme.palette;
    expect(palette.inputBorder, Colors.blue);
    expect(palette.shellBorder, Colors.magenta);
    expect(palette.muted, Colors.gray);
    expect(palette.selected, const Color.fromRGB(30, 40, 60));
    expect(palette.panel, const Color.fromRGB(20, 20, 40));
    expect(palette.accent, Colors.brightBlue);
    expect(palette.background, const Color.fromRGB(0, 20, 40));
  });

  test('unknown theme falls back to default', () {
    NavaTheme.use('nope');
    expect(NavaTheme.current, 'default');
    expect(NavaTheme.palette.inputBorder, Colors.blue);
    expect(NavaTheme.palette.shellBorder, Colors.magenta);
  });

  test('NavaTheme.use 切换调色板，names 列出全部内置主题', () {
    expect(NavaTheme.names, <String>['default', 'dark', 'light', 'tokyonight']);

    NavaTheme.use('tokyonight');
    expect(NavaTheme.current, 'tokyonight');
    expect(NavaTheme.palette.background, const Color(0x1A1B26));
    expect(NavaTheme.palette.inputBorder, const Color(0x7AA2F7));

    NavaTheme.use('light');
    expect(NavaTheme.palette.background, const Color(0xFAFAFC));
  });

  test('每个主题都覆盖全部消息角色', () {
    for (final String name in NavaTheme.names) {
      NavaTheme.use(name);
      expect(
        NavaTheme.palette.message.keys,
        containsAll(TuiRole.values),
        reason: name,
      );
    }
    NavaTheme.use('default');
    expect(NavaTheme.palette.message[TuiRole.tool], Colors.cyan);
    expect(NavaTheme.palette.message[TuiRole.system], Colors.yellow);
    expect(NavaTheme.palette.message[TuiRole.nav], Colors.magenta);
    expect(NavaTheme.palette.message[TuiRole.thinking], Colors.brightBlack);
  });

  test('ThemeView 渲染全部主题名、选中标记与当前标记', () async {
    final NoctermTester tester = await NoctermTester.create(
      size: const Size(100, 30),
    );
    try {
      await tester.pumpComponent(
        ThemeView(names: NavaTheme.names, selected: 2, current: 'default'),
      );
      await tester.pump();

      expect(tester.terminalState, containsText('主题'));
      for (final String name in NavaTheme.names) {
        expect(tester.terminalState, containsText(name));
      }
      expect(tester.terminalState, containsText('> light'));
      expect(tester.terminalState, containsText('当前'));
    } finally {
      tester.dispose();
    }
  });

  test('controller.setTheme 应用主题并刷新；/theme 走浮层确认', () async {
    final ConatusTuiController controller = _controller('theme');
    final NoctermTester tester = await NoctermTester.create();
    try {
      await tester.pumpComponent(AgentTui(controller: controller));
      await tester.pump();

      controller.setTheme('light');
      expect(NavaTheme.current, 'light');
      expect(NavaTheme.palette.background, const Color(0xFAFAFC));

      final Future<void> pending = controller.handleLine('/theme');
      await tester.pump();
      expect(controller.themePrompt.open, isTrue);
      controller.themePrompt.move(-1);
      controller.themePrompt.confirm();
      await pending;
      await tester.pump();

      expect(controller.themePrompt.open, isFalse);
      expect(NavaTheme.current, 'dark');
      expect(
        controller.transcript.messages.map((TuiMessage m) => m.text),
        contains('已切换到「dark」主题。'),
      );
    } finally {
      tester.dispose();
    }
  });

  test('[tui] 配置缺省 default / animations true', () {
    final ConatusCodeConfig config = loadConfig(path: _writeToml('[agent]\n'));
    expect(config.tui.theme, 'default');
    expect(config.tui.animations, isTrue);
  });

  test('[tui] theme 与 animations 解析', () {
    final ConatusCodeConfig config = loadConfig(
      path: _writeToml('[tui]\ntheme = "tokyonight"\nanimations = false\n'),
    );
    expect(config.tui.theme, 'tokyonight');
    expect(config.tui.animations, isFalse);
  });

  test('首次启动模板包含注释的 [tui] 示例', () {
    final Directory dir = Directory.systemTemp.createTempSync('nava-tpl');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String path = '${dir.path}${Platform.pathSeparator}$kConfigFileName';
    loadConfig(path: path);
    final String template = File(path).readAsStringSync();
    expect(template, contains('# [tui]'));
    expect(template, contains('theme = "default"'));
    expect(template, contains('animations = true'));
  });
}
