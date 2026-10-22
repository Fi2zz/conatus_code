/// OpenCode Console / Go 网关的会话关联约定。
///
/// 文档：<https://opencode.ai/v2/docs/console/harnesses>。Go 计划要求每个会话
/// 发送稳定的 `x-opencode-session: ses_...`，用于路由与 prompt cache 复用；
/// 客户端还应以自己的 User-Agent 标识身份。
library;

/// OpenCode 网关的会话头名（文档值）。
const String kOpenCodeSessionHeader = 'x-opencode-session';

/// 面向 OpenCode 网关时的默认客户端标识。
const String kOpenCodeDefaultUserAgent = 'nava/0.1.0';

/// 是否 OpenCode 推理网关（host 为 `opencode.ai`）。
bool isOpenCodeBaseUrl(String baseUrl) =>
    Uri.tryParse(baseUrl)?.host == 'opencode.ai';

/// nava 会话 id → OpenCode 会话头值：`session_<uuid>` → `ses_<uuid>`。
String openCodeSessionId(String sessionId) {
  final String bare = sessionId.startsWith('session_')
      ? sessionId.substring('session_'.length)
      : sessionId;
  return bare.startsWith('ses_') ? bare : 'ses_$bare';
}
