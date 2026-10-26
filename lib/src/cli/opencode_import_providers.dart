/// OpenCode `providers` JSON → nava `[providers.*]` / `[models.*]`。
///
/// 只导入显式声明了 `baseURL` 与密钥（或 `{env:NAME}`）的提供商；OAuth
/// 登录态不在配置文件里，无法自动迁移，会告警跳过。
library;

import 'opencode_import_fields.dart';
import 'opencode_import_types.dart';

/// 映射 `providers` 对象。
List<ImportedProvider> mapOpenCodeProviders(
  Object? raw,
  String source,
  List<String> warnings,
) {
  if (raw == null) return const <ImportedProvider>[];
  if (raw is! Map) {
    warnings.add('$source: providers 必须是对象，已忽略。');
    return const <ImportedProvider>[];
  }
  final List<ImportedProvider> result = <ImportedProvider>[];
  for (final MapEntry<Object?, Object?> entry in raw.entries) {
    final ImportedProvider? provider = _provider(
      entry.key.toString().trim(),
      entry.value,
      source,
      warnings,
    );
    if (provider != null) result.add(provider);
  }
  return result;
}

ImportedProvider? _provider(
  String name,
  Object? raw,
  String source,
  List<String> warnings,
) {
  if (name.isEmpty) {
    warnings.add('$source: providers 有空名字，已跳过。');
    return null;
  }
  if (raw is! Map) {
    warnings.add('$source: providers.$name 必须是对象，已跳过。');
    return null;
  }
  final Map<Object?, Object?> settings = raw['settings'] is Map
      ? (raw['settings'] as Map).cast<Object?, Object?>()
      : const <Object?, Object?>{};
  final String? baseUrl =
      _first(settings, <String>['baseURL', 'baseUrl', 'base_url']) ??
      _first(raw, <String>['baseURL', 'baseUrl', 'base_url']);
  if (baseUrl == null) {
    warnings.add('$source: providers.$name 缺少 baseURL，已跳过。');
    return null;
  }
  final String? rawKey =
      _first(settings, <String>['apiKey', 'api_key']) ??
      _first(raw, <String>['apiKey', 'api_key']);
  final _Key key = _key(rawKey, source, name, warnings);
  if (key.value == null && key.credential == null) {
    warnings.add(
      '$source: providers.$name 没有可导入的 apiKey / credential，已跳过'
      '（OAuth 登录态不在配置文件里）。',
    );
    return null;
  }
  return ImportedProvider(
    name: name,
    baseUrl: baseUrl,
    type: _type(openCodeString(raw['package'])),
    apiKey: key.value,
    credentialKey: key.credential,
    models: _models(raw['models'], source, name, warnings),
  );
}

class _Key {
  const _Key(this.value, this.credential);

  final String? value;
  final String? credential;
}

_Key _key(
  String? raw,
  String source,
  String name,
  List<String> warnings,
) {
  if (raw == null) return const _Key(null, null);
  final RegExpMatch? env = RegExp(r'^\{env:([A-Za-z_][A-Za-z0-9_]*)\}$').firstMatch(raw);
  if (env != null) return _Key(null, env.group(1));
  if (raw.startsWith('{file:')) {
    warnings.add('$source: providers.$name 的 {file:...} 密钥无法导入，已跳过。');
    return const _Key(null, null);
  }
  return _Key(raw, null);
}

String _type(String? package) {
  final String value = package?.toLowerCase() ?? '';
  if (value.contains('anthropic')) return 'anthropic';
  if (value.contains('responses')) return 'kimi';
  return 'openai';
}

List<ImportedModel> _models(
  Object? raw,
  String source,
  String provider,
  List<String> warnings,
) {
  if (raw == null) return const <ImportedModel>[];
  if (raw is! Map) {
    warnings.add('$source: providers.$provider.models 必须是对象，已忽略。');
    return const <ImportedModel>[];
  }
  final List<ImportedModel> result = <ImportedModel>[];
  for (final MapEntry<Object?, Object?> entry in raw.entries) {
    if (entry.value is! Map) continue;
    final Map<Object?, Object?> model =
        (entry.value as Map).cast<Object?, Object?>();
    final String rawId =
        openCodeString(model['modelID']) ?? entry.key.toString().trim();
    if (rawId.isEmpty) continue;
    final int hash = rawId.indexOf('#');
    if (hash > 0) {
      warnings.add('$source: providers.$provider.models 的 $rawId 含 #variant，已去掉。');
    }
    final String id = hash > 0 ? rawId.substring(0, hash) : rawId;
    final Object? limit = model['limit'];
    final int context = limit is Map && limit['context'] is int
        ? limit['context'] as int
        : 0;
    result.add(
      ImportedModel(
        model: id,
        displayName: openCodeString(model['name']) ?? '',
        maxContext: context,
      ),
    );
  }
  return result;
}

String? _first(Map<Object?, Object?> table, List<String> keys) {
  for (final String key in keys) {
    final String? value = openCodeString(table[key]);
    if (value != null) return value;
  }
  return null;
}
