/// 装配：把 [ProviderRegistry] 作为 `'providers'` 服务提供到上下文。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_credentials/conatus_credentials.dart';

import 'provider_profile.dart';
import 'provider_registry.dart';

/// `ctx.providers`：当前上下文可见的注册表。
extension ProvidersContext on Context {
  /// 取注册表；未提供返回 `null`。
  ProviderRegistry? get providers => get<ProviderRegistry>('providers');
}

/// 提供注册表为 `'providers'` 服务（数据源是 config.toml 的 `[providers.*]`）。
///
/// [currentName] 缺省取列表首个；[credentials] 是 Key 的回退来源。
ProviderRegistry provideProviders(
  Context ctx, {
  required List<ProviderProfile> providers,
  String? currentName,
  Credentials? credentials,
}) {
  final ProviderRegistry registry = ProviderRegistry(
    profiles: providers,
    currentName:
        currentName ?? (providers.isEmpty ? null : providers.first.name),
    credentials: credentials,
  );
  ctx.provide('providers', registry);
  return registry;
}
