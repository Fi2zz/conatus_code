/// 首帧后装配任务：顺序、幂等、失败隔离。
library;

import 'package:conatus_code/src/tui/deferred_startup.dart';
import 'package:test/test.dart';

void main() {
  test('start 之前不执行；按登记顺序执行一次', () async {
    final List<String> ran = <String>[];
    final DeferredStartup deferred = DeferredStartup(warn: (_) {});
    deferred.add('a', () async => ran.add('a'));
    deferred.add('b', () async => ran.add('b'));

    expect(deferred.started, isFalse);
    expect(deferred.completed, isFalse);
    expect(ran, isEmpty);

    await deferred.start();
    expect(ran, <String>['a', 'b']);
    expect(deferred.completed, isTrue);

    await deferred.start();
    expect(ran, <String>['a', 'b']);
  });

  test('单个任务失败只告警，不阻断后续任务', () async {
    final List<String> ran = <String>[];
    final List<String> warnings = <String>[];
    final DeferredStartup deferred = DeferredStartup(warn: warnings.add);
    deferred.add('坏任务', () async => throw StateError('boom'));
    deferred.add('好任务', () async => ran.add('ok'));

    await deferred.start();

    expect(ran, <String>['ok']);
    expect(warnings.single, contains('坏任务'));
    expect(deferred.completed, isTrue);
  });
}
