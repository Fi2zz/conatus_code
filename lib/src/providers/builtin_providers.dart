/// 内置的具体提供商：豆包与 DeepSeek。
///
/// 从 `conatus_llm` 迁出：`conatus_llm` 只保留通用 wire 层与回退机制，
/// 「有哪些具体提供商、各自的端点与默认模型」属于提供商管理（本模块）。
///
/// 这里只提供显式构造的便捷类，**不含缺省回退链**：运行时用哪个提供商由
/// 注册表配置（`providers.json`）或调用方注入的 `llm` 决定。
library;

import 'package:conatus_llm/conatus_llm.dart';

/// 豆包提供商。走火山引擎方舟的 OpenAI 兼容端点。
///
/// 默认端点 `https://ark.cn-beijing.volces.com/api/v3`，默认模型
/// `doubao-seed-1-8-251228`，凭据键 `ARK_API_KEY`（经注入的 `Credentials`
/// 解析，构造时需显式传 `apiKey` 或 `credentials` 实例）。
class DoubaoProvider extends OpenAiCompatibleProvider {
  DoubaoProvider({
    super.apiKey,
    String? baseUrl,
    String? model,
    super.apiStyle,
    super.userAgent,
    super.client,
    super.credentials,
    super.credentialKey = 'ARK_API_KEY',
    Duration? timeout,
  }) : super(
          name: 'doubao',
          baseUrl: baseUrl ?? 'https://ark.cn-beijing.volces.com/api/v3',
          model: model ?? 'doubao-seed-1-8-251228',
          timeout: timeout ?? const Duration(seconds: 60),
        );
}

/// DeepSeek 提供商。
///
/// 默认端点 `https://api.deepseek.com`，默认模型 `deepseek-flash`，凭据键
/// `DEEPSEEK_API_KEY`（经注入的 `Credentials` 解析）。
class DeepSeekProvider extends OpenAiCompatibleProvider {
  DeepSeekProvider({
    super.apiKey,
    String? baseUrl,
    String? model,
    super.apiStyle,
    super.userAgent,
    super.client,
    super.credentials,
    super.credentialKey = 'DEEPSEEK_API_KEY',
    Duration? timeout,
  }) : super(
          name: 'deepseek',
          baseUrl: baseUrl ?? 'https://api.deepseek.com',
          model: model ?? 'deepseek-flash',
          timeout: timeout ?? const Duration(seconds: 60),
        );
}

