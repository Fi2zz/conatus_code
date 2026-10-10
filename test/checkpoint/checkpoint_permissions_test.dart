/// E-12：检查点落盘权限收紧——归档 / index 0600、会话目录与影子仓库目录 0700。
///
/// 检查点是工作区内容的**第二落盘面**（含用户可能误留的密钥），此前权限随
/// umask（目录 0755 / 文件 0644），同机其他用户可读。此处对齐 config.toml 与
/// 会话 JSONL 的 600 策略。Windows 无 POSIX 权限位，跳过。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

/// 路径权限位（低 12 位）；目录与文件同语义。
int _bits(String path) {
  final FileStat stat = FileStat.statSync(path);
  return stat.mode & 0xFFF;
}

/// 建归档 store；返回 (store, 工作区根, projectDir)。
(ArchiveCheckpointStore, String, String) _archiveStore() {
  final Directory dir = Directory.systemTemp.createTempSync('nava-cp-perm');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String root = '${dir.path}${Platform.pathSeparator}ws';
  final String projectDir = '$root${Platform.pathSeparator}.conatus';
  Directory(projectDir).createSync(recursive: true);
  return (
    ArchiveCheckpointStore(root: root, projectDir: projectDir),
    root,
    projectDir,
  );
}

void main() {
  test('归档快照后：归档与 index 为 0600、会话目录 0700', () async {
    if (Platform.isWindows) return;
    final (ArchiveCheckpointStore store, String root, _) = _archiveStore();
    File('$root${Platform.pathSeparator}a.txt').writeAsStringSync('v0');

    await store.snapshot('s1', 0);

    expect(_bits(store.archiveFile('s1', 0).path), 0x180); // 0o600
    expect(_bits(store.indexFile('s1').path), 0x180); // 0o600
    expect(_bits(store.sessionDir('s1').path), 0x1C0); // 0o700
  });

  test('影子仓库快照后：checkpoints 目录 0700、索引 0600', () async {
    if (Platform.isWindows) return;
    if (!await const ProcessGitRunner().available()) return;
    final Directory ws = Directory.systemTemp.createTempSync(
      'nava-shadow-perm',
    );
    addTearDown(() => ws.deleteSync(recursive: true));
    final String projectDir = '${ws.path}${Platform.pathSeparator}.conatus';
    Directory(projectDir).createSync();
    Process.runSync('git', <String>['init', '--quiet', ws.path]);
    File('${ws.path}${Platform.pathSeparator}a.txt').writeAsStringSync('v0');
    final GitShadowStore store = GitShadowStore(
      root: ws.path,
      projectDir: projectDir,
    );

    await store.snapshot('s1', 0);

    expect(_bits(store.sessionRoot()), 0x1C0); // 0o700
    expect(_bits(store.indexFile('s1').path), 0x180); // 0o600
  });

  test('打开 store 时迁移旧检查点目录权限为 0700', () async {
    if (Platform.isWindows) return;
    final Directory dir = Directory.systemTemp.createTempSync(
      'nava-cp-migrate',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final String root = '${dir.path}${Platform.pathSeparator}ws';
    final String projectDir = '$root${Platform.pathSeparator}.conatus';
    final Directory checkpointRoot = Directory(
      '$projectDir${Platform.pathSeparator}checkpoints',
    )..createSync(recursive: true);
    final Directory legacy = Directory(
      '${checkpointRoot.path}${Platform.pathSeparator}s-old',
    )..createSync();
    File(
      '${legacy.path}${Platform.pathSeparator}deadbeef',
    ).writeAsStringSync('旧检查点');
    // 旧版本的宽松权限（目录 0755、文件 0644）。
    Process.runSync('chmod', <String>['755', checkpointRoot.path]);
    Process.runSync('chmod', <String>[
      '644',
      '${legacy.path}${Platform.pathSeparator}deadbeef',
    ]);
    expect(_bits(checkpointRoot.path), 0x1ED); // 0o755

    await openCheckpointStore(
      config: const CheckpointConfig(backend: CheckpointBackend.archive),
      root: root,
      projectDir: projectDir,
    );

    expect(_bits(checkpointRoot.path), 0x1C0); // 0o700
  });
}
