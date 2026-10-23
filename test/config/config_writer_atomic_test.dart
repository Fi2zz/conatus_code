/// 原子写配置：同目录临时文件、0600、无残留、符号链接写穿。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nava-atomic-');
    path = '${dir.path}${Platform.pathSeparator}config.toml';
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('写入内容并创建父目录', () {
    final String nested =
        '${dir.path}${Platform.pathSeparator}nested'
        '${Platform.pathSeparator}config.toml';

    writeFileAtomic(nested, '[llm]\n');

    expect(File(nested).readAsStringSync(), '[llm]\n');
  });

  test('不留临时文件', () {
    writeFileAtomic(path, 'x');

    expect(File(path).readAsStringSync(), 'x');
    expect(
      dir.listSync().map((FileSystemEntity entity) => entity.path),
      <String>[path],
    );
  });

  test('覆盖已有文件同样原子，不残留临时文件', () {
    writeFileAtomic(path, 'old');
    writeFileAtomic(path, 'new');

    expect(File(path).readAsStringSync(), 'new');
    expect(dir.listSync(), hasLength(1));
  });

  test('POSIX 下权限为 0600', () {
    writeFileAtomic(path, 'secret');

    if (Platform.isWindows) return;
    expect(File(path).statSync().mode & 0x1FF, 0x180);
  });

  test('显式 mode 生效', () {
    writeFileAtomic(path, 'x', mode: 0x1A4); // 0644

    if (Platform.isWindows) return;
    expect(File(path).statSync().mode & 0x1FF, 0x1A4);
  });

  group('.opencode 只读', () {
    test('字面路径拒绝且不创建父目录', () {
      final String protectedPath =
          '${dir.path}${Platform.pathSeparator}.opencode'
          '${Platform.pathSeparator}config.toml';

      expect(
        () => writeFileAtomic(protectedPath, 'x'),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(protectedPath).existsSync(), isFalse);
      expect(
        Directory('${dir.path}${Platform.pathSeparator}.opencode').existsSync(),
        isFalse,
      );
    });

    test('父目录是符号链接指向 .opencode 时拒绝', () {
      final Directory protectedDir = Directory(
        '${dir.path}${Platform.pathSeparator}.opencode',
      )..createSync();
      final String linkPath = '${dir.path}${Platform.pathSeparator}link';
      Link(linkPath).createSync(protectedDir.path);
      final String target = '$linkPath${Platform.pathSeparator}config.toml';

      expect(
        () => writeFileAtomic(target, 'x'),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(target).existsSync(), isFalse);
    });

    test('NAVA_HOME 指向 .opencode：loadConfig 不初始化模板', () {
      final String home = '${dir.path}${Platform.pathSeparator}.opencode';

      expect(
        () => loadConfig(env: <String, String>{kConfigHomeEnv: home}),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        File('$home${Platform.pathSeparator}config.toml').existsSync(),
        isFalse,
      );
    });

    test('OAuth 令牌目录派生阶段就拒绝', () {
      expect(
        () => resolveOAuthTokenDir(
          env: <String, String>{
            kConfigHomeEnv: '${dir.path}${Platform.pathSeparator}.opencode',
          },
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  test('符号链接：写穿目标，不切断链接', () {
    final File real = File(
      '${dir.path}${Platform.pathSeparator}dotfiles-config.toml',
    )..writeAsStringSync('old');
    final String linkPath = '${dir.path}${Platform.pathSeparator}config.toml';
    Link(linkPath).createSync(real.path);

    writeFileAtomic(linkPath, 'new');

    expect(FileSystemEntity.isLinkSync(linkPath), isTrue);
    expect(real.readAsStringSync(), 'new');
    expect(File(linkPath).readAsStringSync(), 'new');
  });
}
