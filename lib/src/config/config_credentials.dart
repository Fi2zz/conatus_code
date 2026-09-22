/// 由 `config.toml` 的 `[credentials]` 表提供凭据：只读，叠在环境变量之后。
library;

import 'package:conatus_credentials/conatus_credentials.dart';

import 'config_schema.dart';

/// 配置凭据来源。
///
/// 取值顺序：先问 [base]（缺省 [EnvCredentials]），未命中再查配置文件 ——
/// 即**环境变量优先**，避免配置文件覆盖 CI 的密钥注入。
class ConfigCredentials extends Credentials {
  ConfigCredentials(this._config, {Credentials? base})
      : _base = base ?? EnvCredentials();

  final ConatusCodeConfig _config;
  final Credentials _base;

  @override
  Credential? get(String key) {
    final Credential? fromBase = _base.get(key);
    if (fromBase != null) return fromBase;
    final String? value = _config.credentials[key];
    if (value == null) return null;
    return Credential(key: key, value: value);
  }

  @override
  List<String> get keys => <String>{
        ..._base.keys,
        ..._config.credentials.keys,
      }.toList(growable: false);

  @override
  Stream<Credential> get changes => _base.changes;

  @override
  Future<void> update(String key, String value) async {
    throw const CredentialsException('read-only', '配置文件凭据是只读来源。');
  }

  @override
  Future<void> refresh() => _base.refresh();

  @override
  void close() => _base.close();
}
