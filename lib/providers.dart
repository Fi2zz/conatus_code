/// conatus_code 的模型提供商管理：`ProviderProfile` 装配与只读注册表。
///
/// 数据源是 `~/.nava/config.toml` 的 `[providers.*]` 表（见
/// `lib/src/config/`）；本入口供 `/provider`（只读展示）与按 profile 构造
/// OpenAI 兼容 `LlmProvider`。
///
/// **实验性**：API 可能在没有 major 版本变更的情况下调整，勿在生产环境依赖。
library;

export 'src/providers/builtin_providers.dart'
    show DeepSeekProvider, DoubaoProvider;
export 'src/providers/model_catalog.dart'
    show ModelCapability, ModelSpec, ProviderPreset, kProviderPresets;
export 'src/providers/models_dev.dart'
    show ModelsDevClient, ModelsDevException, ModelsDevModel, keepForCoding;
export 'src/providers/provider_profile.dart' show ProviderProfile;
export 'src/providers/provider_registry.dart' show ProviderRegistry;
export 'src/providers/providers_provider.dart'
    show ProvidersContext, provideProviders;
