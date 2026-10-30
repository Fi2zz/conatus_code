/// 重命名 / 删除测试的共用装配：持久化会话、故事线日志与归档检查点。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/fs_tools.dart';
import 'package:conatus_code/src/checkpoint_config_adapter.dart';
import 'package:conatus_code/src/tui/session_ui_state.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

/// 当前会话 id。
const String renameCurrentId = 'session_current';

/// 另一个已持久化会话 id。
const String renameOtherId = 'session_other';

/// 固定回复的假 provider。
class StubProvider implements LlmProvider {
  @override
  String get name => 'stub';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async => const LlmResult(content: 'ok', provider: 'stub', model: 'm');

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) => const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

/// 装配后的测试夹具。
class RenameFixture {
  RenameFixture({
    required this.controller,
    required this.app,
    required this.sessions,
    required this.sessionsDir,
    required this.storyLog,
    required this.storyLogDir,
    required this.checkpoint,
    required this.store,
  });

  /// 控制器。
  final ConatusTuiController controller;

  /// 根上下文。
  final Context app;

  /// 会话仓库。
  final SessionStore sessions;

  /// 会话 JSONL 目录。
  final Directory sessionsDir;

  /// 故事线日志（服务未装配时仅作占位）。
  final InMemorySessionLog storyLog;

  /// 故事线日志目录（关闭故事层时删除走这里）。
  final Directory storyLogDir;

  /// 检查点管理器。
  final CheckpointManager checkpoint;

  /// 归档检查点存储（用于断言目录被清空）。
  final ArchiveCheckpointStore store;

  /// 某会话的 JSONL 文件。
  File jsonl(String id) =>
      File('${sessionsDir.path}${Platform.pathSeparator}$id.jsonl');

  /// 某会话的检查点目录。
  String checkpointSessionDir(String id) => store.sessionDir(id).path;
}

/// 建一个带当前会话 + 旧持久化会话的控制器。
///
/// [start] 为 `false` 时跳过 `controller.start()`，留给 `AgentTui` 挂载时启动
/// （根组件 `initState` 会调一次，重复调用会重复注册工具）。
Future<RenameFixture> buildRenameFixture({
  bool start = true,
  bool storyEnabled = true,
  SessionUiStateStore? uiState,
}) async {
  final Directory dir = Directory.systemTemp.createTempSync(
    'nava-rename-delete-',
  );
  addTearDown(() => dir.deleteSync(recursive: true));
  final Directory sessionsDir = Directory(
    '${dir.path}${Platform.pathSeparator}sessions',
  )..createSync();
  final Directory projectDir = Directory(
    '${dir.path}${Platform.pathSeparator}project',
  )..createSync();

  final Context app = Context.root();
  provideTools(app);
  final FileSystem fs = provideFileSystemLocal(
    app,
    fs: LocalFileSystem(cwd: dir.path),
  );
  provideFsTools(app, options: FsToolOptions(fs: fs, enableSearch: false));
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[StubProvider()]));
  final InMemorySessionLog storyLog = InMemorySessionLog();
  final Directory storyLogDir = Directory(
    '${dir.path}${Platform.pathSeparator}story-log',
  );
  app.provide('storyLogDir', storyLogDir.path);
  if (storyEnabled) provideSessionLog(app, log: storyLog);
  final SessionStore sessions = provideSessions(
    app,
    persistence: JsonlSessionPersistence(dir: sessionsDir.path),
  );
  final CheckpointOptions options = checkpointOptions(const CheckpointConfig());
  final ArchiveCheckpointStore store = ArchiveCheckpointStore(
    root: dir.path,
    projectDir: projectDir.path,
    policy: options.policy,
  );
  final CheckpointManager checkpoint = CheckpointManager(
    store: store,
    options: options,
  );
  app.provide('checkpointManager', checkpoint);
  if (uiState != null) app.provide('sessionUiState', uiState);

  final Session current = sessions.create(id: renameCurrentId);
  current.append(kUserMessageEvent, data: <String, Object?>{'text': '当前会话的问题'});
  final Session other = sessions.create(id: renameOtherId);
  other.append(
    kUserMessageEvent,
    data: <String, Object?>{
      'text': 'Legacy question that is definitely longer than forty chars',
    },
  );
  sessions.close(renameOtherId);
  await sessions.flush();

  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    initialSession: renameCurrentId,
    modelLabel: 'stub',
    storyEnabled: storyEnabled,
    onExit: () {},
  );
  if (start) {
    await controller.start();
    await controller.checkpointSettled;
  }
  addTearDown(() async {
    await controller.checkpointSettled;
    controller.dispose();
    app.dispose();
  });
  return RenameFixture(
    controller: controller,
    app: app,
    sessions: sessions,
    sessionsDir: sessionsDir,
    storyLog: storyLog,
    storyLogDir: storyLogDir,
    checkpoint: checkpoint,
    store: store,
  );
}
