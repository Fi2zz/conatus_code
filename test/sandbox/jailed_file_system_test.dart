import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

/// 断言 [body] 抛 sandboxDenied 的 [FsError]。
void _expectDenied(Future<void> Function() body) {
  expect(
    body,
    throwsA(isA<FsError>().having(
        (FsError e) => e.code, 'code', FsErrorCode.sandboxDenied)),
  );
}

void main() {
  late Directory root;
  late JailedFileSystem fs;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cc-jail-');
    fs = JailedFileSystem(root: root.path);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('读沙箱内文件成功', () async {
    File('${root.path}/a.txt').writeAsStringSync('hello');

    final FsTarget target = await fs.resolve('a.txt');
    expect(await fs.readText(target), 'hello');
  });

  test('读 ../ 越界路径 → sandboxDenied', () async {
    File('${root.path}/../cc-jail-secret.txt').writeAsStringSync('x');
    addTearDown(
        () => File('${root.path}/../cc-jail-secret.txt').deleteSync());

    _expectDenied(() async => fs.resolve('../cc-jail-secret.txt'));
  });

  test('写沙箱内成功', () async {
    final FsTarget target = await fs.resolve('b.txt');

    await fs.writeText(target, 'content');

    expect(File('${root.path}/b.txt').readAsStringSync(), 'content');
  });

  test('写越界相对路径 → sandboxDenied', () async {
    final FsTarget outside =
        await LocalFileSystem(cwd: root.path).resolve('../cc-jail-out.txt');

    _expectDenied(() async => fs.writeText(outside, 'x'));
  });

  test('listDir 正常', () async {
    File('${root.path}/a.txt').writeAsStringSync('1');
    Directory('${root.path}/sub').createSync();

    final FsTarget target = await fs.resolve('.');
    final List<FsDirEntry> entries = await fs.listDir(target);

    expect(entries.map((FsDirEntry e) => e.name),
        containsAll(<String>['a.txt', 'sub']));
    expect(entries.firstWhere((FsDirEntry e) => e.name == 'a.txt').type,
        FsFileType.file);
    expect(entries.firstWhere((FsDirEntry e) => e.name == 'sub').type,
        FsFileType.directory);
  });

  test('editText 替换成功', () async {
    File('${root.path}/a.txt').writeAsStringSync('hello world');
    final FsTarget target = await fs.resolve('a.txt');

    final FsEditOutcome outcome = await fs.editText(
        target, const FsEditRequest(oldString: 'world', newString: 'dart'));

    expect(outcome.after, 'hello dart');
    expect(File('${root.path}/a.txt').readAsStringSync(), 'hello dart');
  });

  test('remove 删除文件', () async {
    File('${root.path}/a.txt').writeAsStringSync('x');
    final FsTarget target = await fs.resolve('a.txt');

    await fs.remove(target);

    expect(File('${root.path}/a.txt').existsSync(), isFalse);
  });

  test('stat 返回元信息', () async {
    File('${root.path}/a.txt').writeAsStringSync('x');
    final FsTarget target = await fs.resolve('a.txt');

    final FsInfo? info = await fs.stat(target);

    expect(info, isNotNull);
    expect(info!.type, FsFileType.file);
  });
}
