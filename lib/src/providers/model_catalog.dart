/// 模型规格与常见提供商的候选清单。
///
/// 模型数据**不内置**：运行期由 `models_dev.dart` 从 models.dev/api.json 拉取
/// 解析。本文件只定义统一结构 [ModelSpec]（拉取结果与 config `[models.*]`
/// 共用的内部表示）与 [kProviderPresets]（`/provider add` 里「已注册 provider」
/// 的候选列表：models.dev 的 provider id + 常见编码端点）。
library;

/// 能力标记（OpenCode 风格，见 `capabilities = [...]`）。
abstract final class ModelCapability {
  /// 支持工具调用。
  static const String toolUse = 'tool_use';

  /// 支持推理（thinking）。
  static const String alwaysThinking = 'always_thinking';

  /// 支持图像输入。
  static const String imageIn = 'image_in';

  /// 支持视频输入。
  static const String videoIn = 'video_in';

  /// 支持 PDF 输入。
  static const String pdfIn = 'pdf_in';

  /// 支持音频输入。
  static const String audioIn = 'audio_in';
}

/// 单个模型的规格（内部统一表示）。
class ModelSpec {
  const ModelSpec({
    required this.provider,
    required this.model,
    this.displayName = '',
    this.maxContext = 0,
    this.inputPerMillion = 0,
    this.outputPerMillion = 0,
    this.capabilities = const <String>{},
  });

  /// 所属提供商（config provider 名或内置 id）。
  final String provider;

  /// API 模型 id。
  final String model;

  /// 展示名；空则用 [model]。
  final String displayName;

  /// 上下文窗口（token）；`0` 表示未知。
  final int maxContext;

  /// 每百万输入 token 的成本（美元）。
  final double inputPerMillion;

  /// 每百万输出 token 的成本（美元）。
  final double outputPerMillion;

  /// 能力标记（[ModelCapability] 常量）。
  final Set<String> capabilities;

  /// 是否支持图像输入。
  bool get supportsImage =>
      capabilities.contains(ModelCapability.imageIn) ||
      capabilities.contains(ModelCapability.pdfIn);
}

/// 常见提供商的候选：models.dev 的 provider id + 展示名 + OpenAI 兼容端点。
///
/// 端点手工维护（models.dev 只给模型数据不给端点）；用户选了某 provider 后，
/// 运行期从 models.dev 拉该 id 的模型清单，端点写回预设值。
class ProviderPreset {
  const ProviderPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
  });

  /// models.dev 的 provider id（如 `'deepseek'`）。
  final String id;

  /// 展示名。
  final String name;

  /// OpenAI 兼容端点根地址（写回 config.toml 的 `base_url`）。
  final String baseUrl;
}

/// 常见编码提供商的候选清单（`/provider add` 的来源选择）。
const List<ProviderPreset> kProviderPresets = <ProviderPreset>[
  ProviderPreset(id: 'anthropic', name: 'Anthropic', baseUrl: 'https://api.anthropic.com/v1'),
  ProviderPreset(id: 'openai', name: 'OpenAI', baseUrl: 'https://api.openai.com/v1'),
  ProviderPreset(id: 'google', name: 'Google Gemini', baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai'),
  ProviderPreset(id: 'deepseek', name: 'DeepSeek', baseUrl: 'https://api.deepseek.com/v1'),
  ProviderPreset(id: 'moonshotai', name: 'Moonshot AI', baseUrl: 'https://api.moonshot.cn/v1'),
  ProviderPreset(id: 'xai', name: 'xAI', baseUrl: 'https://api.x.ai/v1'),
  ProviderPreset(id: 'zhipuai', name: 'Zhipu AI', baseUrl: 'https://open.bigmodel.cn/api/paas/v4'),
  ProviderPreset(id: 'minimax', name: 'MiniMax', baseUrl: 'https://api.minimaxi.com/v1'),
  ProviderPreset(id: 'stepfun', name: 'StepFun', baseUrl: 'https://api.stepfun.com/v1'),
  ProviderPreset(id: 'alibaba', name: 'Alibaba (Qwen)', baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1'),
  ProviderPreset(id: 'volcengine', name: 'Volcengine Ark', baseUrl: 'https://ark.cn-beijing.volces.com/api/v3'),
  ProviderPreset(id: 'volcengine-coding-plan', name: 'Ark Coding Plan', baseUrl: 'https://ark.cn-beijing.volces.com/api/coding/v3'),
  ProviderPreset(id: 'mistral', name: 'Mistral', baseUrl: 'https://api.mistral.ai/v1'),
  ProviderPreset(id: 'groq', name: 'Groq', baseUrl: 'https://api.groq.com/openai/v1'),
  ProviderPreset(id: 'cerebras', name: 'Cerebras', baseUrl: 'https://api.cerebras.ai/v1'),
  ProviderPreset(id: 'fireworks-ai', name: 'Fireworks AI', baseUrl: 'https://api.fireworks.ai/inference/v1'),
  ProviderPreset(id: 'openrouter', name: 'OpenRouter', baseUrl: 'https://openrouter.ai/api/v1'),
  ProviderPreset(id: 'opencode-go', name: 'OpenCode Go', baseUrl: 'https://opencode.ai/zen/go/v1'),
];
