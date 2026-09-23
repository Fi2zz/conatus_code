/// 提供商注册表：只读视图、按名查找与 LlmProvider 构造。
library;

import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_llm/conatus_llm.dart';

import 'provider_profile.dart';

/// 模型提供商注册表（只读：数据源是 config.toml 的 `[providers.*]`）。
class ProviderRegistry {
  ProviderRegistry({
    List<ProviderProfile> profiles = const <ProviderProfile>[],
    String? currentName,
    Credentials? credentials,
  })  : _profiles = List<ProviderProfile>.of(profiles),
        _current = currentName ?? (profiles.isEmpty ? null : profiles.first.name),
        _credentials = credentials;

  final List<ProviderProfile> _profiles;

  /// Key 的来源（缺省不注入时配置内 `apiKey` 为空即无 Key）。
  final Credentials? _credentials;

  /// 当前选中的提供商名（装配期决定，运行期不变）。
  final String? _current;

  /// 全部提供商（只读视图）。
  List<ProviderProfile> get profiles =>
      List<ProviderProfile>.unmodifiable(_profiles);

  /// 当前选中的提供商名。
  String? get currentName => _current;

  /// 当前选中的提供商。
  ProviderProfile? get current => byName(_current);

  /// 按名查找；不存在返回 `null`。
  ProviderProfile? byName(String? name) {
    if (name == null) {
      return null;
    }
    for (final ProviderProfile profile in _profiles) {
      if (profile.name == name) {
        return profile;
      }
    }
    return null;
  }

  /// 内存中追加一个提供商；同名已存在时忽略（写回 config.toml 由调用方负责）。
  void add(ProviderProfile profile) {
    if (byName(profile.name) != null) {
      return;
    }
    _profiles.add(profile);
  }

  /// 按名构造 OpenAI 兼容提供商；无此 provider 或没有模型名时返回 `null`。
  ///
  /// Key 解析顺序：配置内 `apiKey` → 注入的 [Credentials]。
  LlmProvider? buildLlm(String name, {String? model}) {
    final ProviderProfile? profile = byName(name);
    final String resolvedModel = model ?? profile?.defaultModel ?? '';
    if (profile == null || resolvedModel.isEmpty) {
      return null;
    }
    return OpenAiCompatibleProvider(
      name: profile.name,
      baseUrl: profile.baseUrl,
      model: resolvedModel,
      credentialKey: profile.credentialKey,
      apiStyle: profile.apiStyle,
      userAgent: profile.userAgent.isEmpty ? kDefaultLlmUserAgent : profile.userAgent,
      apiKey: profile.apiKey.isEmpty ? null : profile.apiKey,
      credentials: _credentials,
    );
  }

  /// 该提供商是否已有可用 Key（配置内 `apiKey` 或凭据服务命中）。
  bool hasKey(String name) {
    final ProviderProfile? profile = byName(name);
    if (profile == null) {
      return false;
    }
    if (profile.apiKey.isNotEmpty) {
      return true;
    }
    return _credentials?.get(profile.credentialKey) != null;
  }
}
