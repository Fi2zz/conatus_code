/// `/diff` 交互式视图与命令：文件树、hunk、按键、空结果与降级占位。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/src/checkpoint_config_adapter.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

/// 固定回复的假 provider（命令测试不需要真正跑模型）。
class _ScriptedProvider implements LlmProvider {
  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async => const LlmResult(content: 'ok', provider: 'scripted', model: 'm');

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) => const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

/// 一个带 hunk 的文件差异。
FileDiff _diff(
  String path, {
  String status = 'modified',
  List<String> lines = const <String>['-old', '+new', ' keep'],
  bool truncated = false,
  bool coarse = false,
  int additions = 1,
  int deletions = 1,
}) {
  return FileDiff(
    path: path,
    status: status,
    hunks: <DiffHunk>[
      DiffHunk(
        oldStart: 1,
        oldLines: 1,
        newStart: 1,
        newLines: 1,
        lines: lines,
      ),
    ],
    additions: additions,
    deletions: deletions,
    truncated: truncated,
    coarse: coarse,
  );
}

List<FileDiff> _sample() => <FileDiff>[
  _diff('a.txt'),
  _diff('b.txt', status: 'added', lines: <String>['+bee'], deletions: 0),
];

/// 临时工作区 + 检查点管理器；[start] 为 false 时由 AgentTui 触发绑定。
Future<(ConatusTuiController, Context, String)> _build({
  bool start = true,
  void Function(String root)? beforeStart,
}) async {
  final Directory dir = Directory.systemTemp.createTempSync('nava-diff-tui');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String root = dir.path;
  final String projectDir = '$root${Platform.pathSeparator}.conatus';
  Directory(projectDir).createSync();
  final Context app = Context.root();
  provideTools(app);
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[_ScriptedProvider()]));
  final SessionStore sessions = provideSessions(app);
  final CheckpointOptions options = checkpointOptions(const CheckpointConfig());
  app.provide(
    'checkpointManager',
    CheckpointManager(
      store: ArchiveCheckpointStore(
        root: root,
        projectDir: projectDir,
        policy: options.policy,
      ),
      options: options,
    ),
  );
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    modelLabel: 'mock',
    onExit: () {},
  )..diffWorkdir = root;
  beforeStart?.call(root);
  if (start) {
    await controller.start();
    await controller.checkpointSettled;
  }
  return (controller, app, root);
}

void _write(String root, String rel, String content) {
  final File file = File('$root${Platform.pathSeparator}$rel');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

String _read(String root, String rel) =>
    File('$root${Platform.pathSeparator}$rel').readAsStringSync();

Future<void> _until(bool Function() cond) async {
  for (int i = 0; i < 400 && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(cond(), isTrue, reason: '条件未在超时内成立');
}

void main() {
  test('渲染文件树与 hunk，n/p 切换文件', () async {
    final NoctermTester tester = await NoctermTester.create();
    try {
      await tester.pumpComponent(
        TuiDiffView(diffs: _sample(), scope: DiffScope.working),
      );

      expect(tester.terminalState, containsText('a.txt'));
      expect(tester.terminalState, containsText('b.txt'));
      expect(tester.terminalState, containsText('-old'));
      expect(tester.terminalState, containsText('+new'));
      expect(tester.terminalState, containsText('工作区'));

      await tester.sendKeyEvent(
        const KeyboardEvent(logicalKey: LogicalKey.keyN),
      );
      expect(tester.terminalState, containsText('+bee'));
      expect(tester.terminalState, isNot(containsText('-old')));

      await tester.sendKeyEvent(
        const KeyboardEvent(logicalKey: LogicalKey.keyP),
      );
      expect(tester.terminalState, containsText('-old'));
    } finally {
      tester.dispose();
    }
  });

  test('j/k 滚动当前文件的 diff', () async {
    final List<String> lines = <String>[
      '-first-line',
      for (int i = 0; i < 40; i++) ' context-$i',
    ];
    final NoctermTester tester = await NoctermTester.create();
    try {
      await tester.pumpComponent(
        TuiDiffView(
          diffs: <FileDiff>[_diff('long.txt', lines: lines)],
          scope: DiffScope.turn,
        ),
      );

      expect(tester.terminalState, containsText('@@ -1,1 +1,1 @@'));
      expect(tester.terminalState, containsText('-first-line'));
      await tester.sendKeyEvent(
        const KeyboardEvent(logicalKey: LogicalKey.keyJ),
      );
      expect(tester.terminalState, isNot(containsText('@@ -1,1 +1,1 @@')));
      expect(tester.terminalState, containsText('context-11'));
      await tester.sendKeyEvent(
        const KeyboardEvent(logicalKey: LogicalKey.keyK),
      );
      expect(tester.terminalState, containsText('@@ -1,1 +1,1 @@'));
    } finally {
      tester.dispose();
    }
  });

  test('d 切换比较范围并回调', () async {
    final List<DiffScope> switched = <DiffScope>[];
    final NoctermTester tester = await NoctermTester.create();
    try {
      await tester.pumpComponent(
        TuiDiffView(
          diffs: _sample(),
          scope: DiffScope.working,
          onSwitchScope: switched.add,
        ),
      );
      expect(tester.terminalState, containsText('工作区'));

      await tester.sendKeyEvent(
        const KeyboardEvent(logicalKey: LogicalKey.keyD),
      );
      expect(tester.terminalState, containsText('本轮'));
      expect(switched, <DiffScope>[DiffScope.turn]);

      await tester.sendKeyEvent(
        const KeyboardEvent(logicalKey: LogicalKey.keyD),
      );
      expect(tester.terminalState, containsText('工作区'));
      expect(switched, <DiffScope>[DiffScope.turn, DiffScope.working]);
    } finally {
      tester.dispose();
    }
  });

  test('m 标记当前文件已读', () async {
    final NoctermTester tester = await NoctermTester.create();
    try {
      await tester.pumpComponent(
        TuiDiffView(diffs: _sample(), scope: DiffScope.working),
      );
      expect(tester.terminalState, isNot(containsText('已读 1')));

      await tester.sendKeyEvent(
        const KeyboardEvent(logicalKey: LogicalKey.keyM),
      );
      expect(tester.terminalState, containsText('已读 1'));

      await tester.sendKeyEvent(
        const KeyboardEvent(logicalKey: LogicalKey.keyN),
      );
      await tester.sendKeyEvent(
        const KeyboardEvent(logicalKey: LogicalKey.keyM),
      );
      expect(tester.terminalState, containsText('已读 2'));
    } finally {
      tester.dispose();
    }
  });

  test('q 与 Esc 关闭视图', () async {
    int closed = 0;
    final NoctermTester tester = await NoctermTester.create();
    try {
      await tester.pumpComponent(
        TuiDiffView(
          diffs: _sample(),
          scope: DiffScope.working,
          onClose: () => closed++,
        ),
      );
      await tester.sendKeyEvent(
        const KeyboardEvent(logicalKey: LogicalKey.keyQ),
      );
      expect(closed, 1);
      await tester.sendEscape();
      expect(closed, 2);
    } finally {
      tester.dispose();
    }
  });

  test('空差异：给出简洁提示而不是空白屏', () async {
    final NoctermTester tester = await NoctermTester.create();
    try {
      await tester.pumpComponent(
        const TuiDiffView(diffs: <FileDiff>[], scope: DiffScope.turn),
      );
      expect(tester.terminalState, containsText('没有可显示的差异'));
      expect(tester.terminalState, containsText('本轮'));
    } finally {
      tester.dispose();
    }
  });

  test('truncated 文件只给占位摘要，不渲染伪 hunk', () async {
    final NoctermTester tester = await NoctermTester.create();
    try {
      await tester.pumpComponent(
        TuiDiffView(
          diffs: <FileDiff>[
            _diff('big.bin', truncated: true, lines: <String>['+bogus']),
          ],
          scope: DiffScope.working,
        ),
      );
      expect(tester.terminalState, containsText('文件过大'));
      expect(tester.terminalState, isNot(containsText('+bogus')));
      expect(tester.terminalState, isNot(containsText('@@')));
    } finally {
      tester.dispose();
    }
  });

  test('coarse 文件标注粗粒度差异但仍展示内容', () async {
    final NoctermTester tester = await NoctermTester.create();
    try {
      await tester.pumpComponent(
        TuiDiffView(
          diffs: <FileDiff>[_diff('coarse.txt', coarse: true)],
          scope: DiffScope.working,
        ),
      );
      expect(tester.terminalState, containsText('粗粒度差异'));
      expect(tester.terminalState, containsText('-old'));
    } finally {
      tester.dispose();
    }
  });

  test('只读：视图没有应用/还原操作', () async {
    final NoctermTester tester = await NoctermTester.create();
    try {
      await tester.pumpComponent(
        TuiDiffView(diffs: _sample(), scope: DiffScope.working),
      );
      expect(tester.terminalState, isNot(containsText('应用')));
      expect(tester.terminalState, isNot(containsText('还原')));
      expect(tester.terminalState, isNot(containsText('apply')));
      expect(tester.terminalState, isNot(containsText('revert')));
    } finally {
      tester.dispose();
    }
  });

  test('/diff 打开视图（缺省 working，无 git 时回落本轮）', () async {
    final (
      ConatusTuiController controller,
      Context app,
      String root,
    ) = await _build(
      beforeStart: (String root) => _write(root, 'a.txt', 'x\n'),
    );
    addTearDown(() async {
      await controller.checkpointSettled;
      controller.dispose();
      app.dispose();
    });

    await controller.handleLine('/diff');

    expect(controller.diffOpen, isTrue);
    expect(controller.diffScope, DiffScope.working);
    expect(
      controller.diffFiles.map((FileDiff diff) => diff.path),
      contains('a.txt'),
    );
  });

  test('/diff turn 显式切到轮次范围', () async {
    final (
      ConatusTuiController controller,
      Context app,
      String root,
    ) = await _build(
      beforeStart: (String root) => _write(root, 'a.txt', 'x\n'),
    );
    addTearDown(() async {
      await controller.checkpointSettled;
      controller.dispose();
      app.dispose();
    });

    await controller.handleLine('/diff turn');

    expect(controller.diffOpen, isTrue);
    expect(controller.diffScope, DiffScope.turn);
    expect(controller.diffFiles, isEmpty, reason: 'turn 0 没有上一轮可比');
    expect(controller.diffNotice, contains('还没有可比较的轮次'));
  });

  test('/diff 参数非法：给用法提示且不打开视图', () async {
    final (
      ConatusTuiController controller,
      Context app,
      String root,
    ) = await _build(
      beforeStart: (String root) => _write(root, 'a.txt', 'x\n'),
    );
    addTearDown(() async {
      await controller.checkpointSettled;
      controller.dispose();
      app.dispose();
    });

    await controller.handleLine('/diff bogus');

    expect(controller.diffOpen, isFalse);
    expect(controller.transcript.messages.last.text, contains('用法：/diff'));
  });

  test('/diff working 用配置 workdir（不是进程 cwd）', () async {
    final Directory dir = Directory.systemTemp.createTempSync('nava-diff-wd');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String root = dir.path;
    final String projectDir = '$root${Platform.pathSeparator}.conatus';
    Directory(projectDir).createSync();
    Process.runSync('git', <String>['init', '-q'], workingDirectory: root);
    Process.runSync('git', <String>[
      'config',
      'user.email',
      't@example.com',
    ], workingDirectory: root);
    Process.runSync('git', <String>[
      'config',
      'user.name',
      'T',
    ], workingDirectory: root);
    _write(root, 'tracked.txt', 'one\n');
    Process.runSync('git', <String>['add', '.'], workingDirectory: root);
    Process.runSync('git', <String>[
      'commit',
      '-qm',
      'init',
    ], workingDirectory: root);
    _write(root, 'tracked.txt', 'two\n');

    final Context app = Context.root();
    addTearDown(app.dispose);
    provideTools(app);
    provideLlm(app, llm: FallbackLlm(<LlmProvider>[_ScriptedProvider()]));
    final SessionStore sessions = provideSessions(app);
    app.provide('workdir', root);
    final CheckpointOptions options = checkpointOptions(
      const CheckpointConfig(),
    );
    app.provide(
      'checkpointManager',
      CheckpointManager(
        store: ArchiveCheckpointStore(
          root: root,
          projectDir: projectDir,
          policy: options.policy,
        ),
        options: options,
      ),
    );
    final ConatusTuiController controller = ConatusTuiController(
      app: app,
      sessions: sessions,
      name: 'test',
      modelLabel: 'mock',
      onExit: () {},
    );
    addTearDown(controller.dispose);
    await controller.start();
    await controller.checkpointSettled;

    await controller.handleLine('/diff');

    expect(
      controller.diffFiles.map((FileDiff diff) => diff.path),
      contains('tracked.txt'),
      reason: 'working 差异必须取自配置 workdir',
    );
  });

  test('TUI 里 /diff 上屏，m 标记、d 切源、q 关闭且不改文件', () async {
    final (
      ConatusTuiController controller,
      Context app,
      String root,
    ) = await _build(
      start: false,
      beforeStart: (String root) => _write(root, 'a.txt', 'x\n'),
    );
    final NoctermTester tester = await NoctermTester.create(
      size: const Size(100, 40),
    );
    try {
      await tester.pumpComponent(AgentTui(controller: controller));
      await _until(() => controller.ready);
      await controller.checkpointSettled;
      await tester.pump();

      await controller.handleLine('/diff');
      await tester.pump();
      expect(tester.terminalState, containsText('a.txt'));

      await tester.sendKeyEvent(
        const KeyboardEvent(logicalKey: LogicalKey.keyM),
      );
      expect(tester.terminalState, containsText('已读 1'));

      await tester.sendKeyEvent(
        const KeyboardEvent(logicalKey: LogicalKey.keyD),
      );
      expect(controller.diffScope, DiffScope.turn);
      await _until(() => controller.diffNotice != null);
      await tester.pump();
      expect(
        controller.diffNotice,
        contains('还没有可比较的轮次'),
        reason: 'turn 0 没有上一轮可比',
      );

      await tester.sendKeyEvent(
        const KeyboardEvent(logicalKey: LogicalKey.keyQ),
      );
      await tester.pump();
      expect(controller.diffOpen, isFalse);
      expect(_read(root, 'a.txt'), 'x\n', reason: '只读：不能改动工作区');
    } finally {
      tester.dispose();
      controller.dispose();
      app.dispose();
    }
  });
}
