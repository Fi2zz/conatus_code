/// 提供商注册表：只读视图、按名查找与 LlmProvider 构造。
library;

import 'package:conatus_code/providers.dart';
import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

ProviderProfile profile(String name, {String? model}) => ProviderProfile(
      name: name,
      baseUrl: 'https://$name.example/v1',
      apiKey: 'key-$name',
      models: <String>[model ?? '$name-model'],
    );

void main() {
  test('构造即定 profiles 与 currentName，缺省取首个', () {
    final ProviderRegistry registry = ProviderRegistry(
      profiles: <ProviderProfile>[profile('a'), profile('b')],
    );

    expect(registry.profiles.map((ProviderProfile p) => p.name),
        <String>['a', 'b']);
    expect(registry.currentName, 'a');
    expect(registry.current!.name, 'a');
    expect(registry.byName('b'), isNotNull);
    expect(registry.byName('nope'), isNull);
  });

  test('显式 currentName 覆盖首个', () {
    final ProviderRegistry registry = ProviderRegistry(
      profiles: <ProviderProfile>[profile('a'), profile('b')],
      currentName: 'b',
    );

    expect(registry.currentName, 'b');
  });

  test('buildLlm 按名构造；无 provider 或模型返回 null', () {
    final ProviderRegistry registry = ProviderRegistry(
      profiles: <ProviderProfile>[profile('a')],
      credentials: InMemoryCredentials(),
    );

    final LlmProvider? llm = registry.buildLlm('a');
    expect(llm, isNotNull);
    expect(llm!.name, 'a');
    expect(registry.buildLlm('a', model: 'x'), isNotNull);
    expect(registry.buildLlm('nope'), isNull);
    expect(
      registry.buildLlm('a', model: ''),
      isNull,
    );
  });

  test('hasKey：apiKey 非空即 true，否则看凭据服务', () {
    final ProviderRegistry registry = ProviderRegistry(
      profiles: <ProviderProfile>[profile('a')],
      credentials: InMemoryCredentials(
        initial: <String, String>{'OTHER': 'v'},
      ),
    );

    expect(registry.hasKey('a'), isTrue);
    expect(registry.hasKey('nope'), isFalse);
  });
}
