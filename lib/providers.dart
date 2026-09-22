/// conatus_code 的模型提供商管理：`ProviderProfile` 注册表、JSON 持久化、
/// 自定义 registry 导入，以及按 profile 构造 OpenAI 兼容 `LlmProvider`。
///
/// 装配出的注册表供 TUI 的 `/provider`（增删改查 / 导入）与 `/model`（切换模型）
/// 命令消费，持久化落在 `<baseDir>/providers.json`。
///
/// **实验性**：API 可能在没有 major 版本变更的情况下调整，勿在生产环境依赖。
library;

export 'src/providers/builtin_providers.dart'
    show DeepSeekProvider, DoubaoProvider;
export 'src/providers/provider_defaults.dart' show kDefaultProviders;
export 'src/providers/provider_import.dart'
    show ProviderImportResult, fetchProviderRegistry, parseProviderRegistry;
export 'src/providers/provider_profile.dart' show ProviderProfile;
export 'src/providers/provider_registry.dart' show ProviderRegistry;
export 'src/providers/provider_store.dart' show ProviderSnapshot, ProviderStore;
export 'src/providers/providers_provider.dart'
    show ProvidersContext, provideProviders;
