/// Seatbelt profile 构建的纯单元测试：不依赖 OS 沙箱后端。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  group('buildSeatbeltProfile', () {
    test('deny-default 基线与核心允许项', () {
      final String profile =
          buildSeatbeltProfile(networkAllowed: false, writableCount: 0);

      expect(profile, contains('(version 1)'));
      expect(profile, contains('(deny default)'));
      expect(profile, contains('(allow process-exec)'));
      expect(profile, contains('(allow file-read* (subpath "/"))'));
      expect(profile, contains('(deny network*)'));
      expect(profile, isNot(contains('(allow network*)')));
    });

    test('networkAllowed = true 时显式放行网络（deny-default 下必须显式 allow）', () {
      final String profile =
          buildSeatbeltProfile(networkAllowed: true, writableCount: 0);

      expect(profile, contains('(allow network*)'));
      expect(profile, isNot(contains('(deny network*)')));
    });

    test('/dev/null、/dev/zero 按字符设备放行', () {
      final String profile =
          buildSeatbeltProfile(networkAllowed: false, writableCount: 0);

      expect(profile, contains('(path "/dev/null")'));
      expect(profile, contains('(path "/dev/zero")'));
      expect(profile, contains('CHARACTER-DEVICE'));
    });

    test('可写根经参数注入，/tmp 用真实路径双写', () {
      final String profile =
          buildSeatbeltProfile(networkAllowed: false, writableCount: 2);

      expect(profile, contains('(param "ROOT")'));
      expect(profile, contains('(param "W0")'));
      expect(profile, contains('(param "W1")'));
      expect(profile, isNot(contains('(param "W2")')));
      expect(profile, contains('(subpath "/private/tmp")'));
      expect(profile, contains('(subpath "/private/var/folders")'));
    });

    test('mach-lookup 为系统服务白名单', () {
      final String profile =
          buildSeatbeltProfile(networkAllowed: false, writableCount: 0);

      expect(profile, contains('(allow mach-lookup'));
      expect(profile, contains('com.apple.trustd.agent'));
      expect(profile, isNot(contains('(allow default)')));
    });

    test('网络放行时才追加 mDNSResponder（断网模式 DNS 也不可达）', () {
      final String off =
          buildSeatbeltProfile(networkAllowed: false, writableCount: 0);
      final String on =
          buildSeatbeltProfile(networkAllowed: true, writableCount: 0);

      expect(off, isNot(contains('mDNSResponder')));
      expect(on, contains('com.apple.mDNSResponder'));
    });
  });

  group('buildSandboxParams', () {
    test('生成 -DROOT 与 -DWn 参数', () {
      final List<String> params = buildSandboxParams(
        root: '/ws',
        writablePaths: const <String>['/home/u/.pub-cache', '/opt/x'],
      );

      expect(params, <String>[
        '-DROOT=/ws',
        '-DW0=/home/u/.pub-cache',
        '-DW1=/opt/x',
      ]);
    });

    test('root 含元字符 → SandboxException', () {
      expect(
        () => buildSandboxParams(root: '/bad"quote', writablePaths: const []),
        throwsA(isA<SandboxException>()),
      );
    });

    test('可写路径含 glob 元字符 → SandboxException', () {
      expect(
        () => buildSandboxParams(root: '/ws', writablePaths: const ['/bad*']),
        throwsA(isA<SandboxException>()),
      );
    });
  });

  group('defaultWritableCaches', () {
    test('展开 HOME 且全部为绝对路径', () {
      final String home = Platform.environment['HOME'] ?? '';
      final Set<String> caches = defaultWritableCaches();

      expect(caches, contains('$home/.pub-cache'));
      expect(caches, contains('$home/.dart_tool'));
      expect(caches, contains('$home/Library/Caches'));
      expect(caches.every((String p) => p.startsWith('/')), isTrue);
    });
  });
}
