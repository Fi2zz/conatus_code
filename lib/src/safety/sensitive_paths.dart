/// 敏感文件识别：私钥、凭据与 `.env` 族。
///
/// 纯规则匹配，不碰文件系统；调用方负责把路径 canonical 化后再传入。
library;

/// 命中类别。
enum SensitiveKind {
  /// `.env` / `.env.*`。
  dotenv,

  /// `id_rsa*` / `id_ed25519*` 等私钥。
  privateKey,

  /// `credentials` / `.aws/credentials` / `.gcp/credentials`。
  credentials,

  /// 用户 `[safety] extra_sensitive_paths` 追加的路径。
  extra,
}

/// 一次命中。
class SensitiveMatch {
  const SensitiveMatch(this.kind, this.path);

  /// 类别。
  final SensitiveKind kind;

  /// 原始路径（用于文案）。
  final String path;
}

const Set<String> _privateKeyNames = <String>{
  'id_rsa',
  'id_dsa',
  'id_ecdsa',
  'id_ed25519',
};

const Set<String> _envExemptions = <String>{
  '.env.example',
  '.env.sample',
  '.env.template',
};

/// 返回命中类别；未命中返回 `null`。
SensitiveMatch? matchSensitivePath(
  String path, {
  Set<String> extraPaths = const <String>{},
}) {
  final String normalized = path.replaceAll('\\', '/').trim();
  if (normalized.isEmpty) return null;
  final String lower = normalized.toLowerCase();
  final List<String> segments = lower
      .split('/')
      .where((String segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (segments.isEmpty) return null;
  final String base = segments.last;
  if (base.endsWith('.pub')) return null;
  if (_envExemptions.contains(base)) return null;
  if (_isCredentials(lower, base)) {
    return SensitiveMatch(SensitiveKind.credentials, path);
  }
  if (_isPrivateKey(base)) {
    return SensitiveMatch(SensitiveKind.privateKey, path);
  }
  if (_matchesExtra(lower, segments, extraPaths)) {
    return SensitiveMatch(SensitiveKind.extra, path);
  }
  if (base == '.env' || base.startsWith('.env.')) {
    return SensitiveMatch(SensitiveKind.dotenv, path);
  }
  return null;
}

/// 面向模型的拒绝文案。
String sensitiveMessage(SensitiveMatch match) {
  final String label = switch (match.kind) {
    SensitiveKind.dotenv => '.env 写入',
    SensitiveKind.privateKey => '私钥文件',
    SensitiveKind.credentials => '凭据文件',
    SensitiveKind.extra => '敏感路径',
  };
  return 'SENSITIVE_PATH: 拒绝访问$label "${match.path}"';
}

bool _isCredentials(String lower, String base) =>
    base == 'credentials' ||
    lower.endsWith('/.aws/credentials') ||
    lower.endsWith('/.gcp/credentials');

bool _isPrivateKey(String base) {
  for (final String name in _privateKeyNames) {
    if (base == name ||
        base.startsWith('$name-') ||
        base.startsWith('${name}_') ||
        base.startsWith('$name.')) {
      return true;
    }
  }
  return false;
}

bool _matchesExtra(
  String lower,
  List<String> segments,
  Set<String> extraPaths,
) {
  for (final String raw in extraPaths) {
    final String entry = raw.replaceAll('\\', '/').trim().toLowerCase();
    if (entry.isEmpty) continue;
    if (entry.contains('/')) {
      if (lower == entry || lower.endsWith('/$entry')) return true;
    } else if (segments.contains(entry)) {
      return true;
    }
  }
  return false;
}
