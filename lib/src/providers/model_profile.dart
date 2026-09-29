/// 模型档案：上下文窗口与真实价格（数据源 models.dev）。
///
/// models.dev 早就把 `limit.context` 与 `cost.input/output` 拉回来了，此前却只
/// 用来填 `/model` 浮层的候选表——窗口和价格都丢掉了，于是：
///
/// * `/cost` 拿两条写死的常数（0.3 / 1.2 美元每百万）当所有模型的价；
/// * 上下文窗口只画在状态栏上，不影响任何行为。
///
/// 本文件把这两项收成一份可查的档案，让成本与窗口真正参与决策。
library;

import 'dart:async';

import 'models_dev.dart';

/// 一个模型的上下文窗口与价格。
///
/// 字段为 0 表示「未知」——models.dev 没这条记录，或该模型没有该维度（如没有
/// 缓存折扣）。**未知不等于 0 元**，消费方须先看 [hasPricing] / [hasContext]。
class ModelProfile {
  const ModelProfile({
    required this.provider,
    required this.model,
    this.contextLength = 0,
    this.inputPerMillion = 0,
    this.outputPerMillion = 0,
    this.cachedInputPerMillion = 0,
  });

  /// 提供商名（config 里的 provider 名）。
  final String provider;

  /// API 模型 id。
  final String model;

  /// 上下文窗口（token）；0 = 未知。
  final int contextLength;

  /// 每百万输入 token 价（美元）。
  final double inputPerMillion;

  /// 每百万输出 token 价（美元）。
  final double outputPerMillion;

  /// 每百万**缓存命中**输入 token 价（美元）；0 = 无缓存折扣信息，按全价算。
  final double cachedInputPerMillion;

  /// 是否有上下文窗口信息。
  bool get hasContext => contextLength > 0;

  /// 是否有价格信息。
  bool get hasPricing => inputPerMillion > 0 || outputPerMillion > 0;

  /// 缓存命中价；未单独给出时退回全价（保守：不虚报折扣）。
  double get effectiveCachedRate =>
      cachedInputPerMillion > 0 ? cachedInputPerMillion : inputPerMillion;

  /// 价目摘要，供 `/cost` 展示。
  String get rateSummary {
    if (!hasPricing) return '费率未知';
    return '\$${_trim(inputPerMillion)}/M in · \$${_trim(outputPerMillion)}/M out';
  }

  static String _trim(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0)
          : value.toStringAsFixed(2);
}

/// models.dev 目录的本地视图：同步查档案，异步预热。
///
/// 装配期不能等网络（冷启动可达 30s），所以设计成「先给未知、按需预热、拿到后
/// 通知」：消费方随时可以同步 [profileOf] 查，查不到就是未知而不是 0。
class ModelProfileStore {
  ModelProfileStore({ModelsDevClient? client, this.cachePath})
      : _client = client ?? ModelsDevClient(cachePath: cachePath);

  /// models.dev 缓存文件路径（通常是 `~/.nava/models.dev.json`）。
  final String? cachePath;

  final ModelsDevClient _client;
  final StreamController<void> _updates = StreamController<void>.broadcast();
  Map<String, Map<String, ModelProfile>> _byProvider =
      <String, Map<String, ModelProfile>>{};

  /// 档案就绪后触发（每次新增数据都发一次），供状态栏等刷新。
  Stream<void> get updates => _updates.stream;

  /// 是否已经拿到过数据。
  bool get warmed => _byProvider.isNotEmpty;

  /// 同步查档案；查不到返回 `null`（未知，不是 0 值档案）。
  ///
  /// 先按 `provider` 精确匹配；provider 名对不上（用户自定义名，如
  /// `arkcli-agent-plan`）时**跨 provider 按模型 id 找一条**——窗口与价格是
  /// 模型属性，provider 名不同不影响。
  ModelProfile? profileOf(String provider, String model) {
    if (model.isEmpty) return null;
    final Map<String, ModelProfile>? exact = _byProvider[provider];
    final ModelProfile? hit = exact?[model];
    if (hit != null) return hit;
    for (final Map<String, ModelProfile> models in _byProvider.values) {
      final ModelProfile? byId = models[model];
      if (byId != null) {
        return ModelProfile(
          provider: provider,
          model: model,
          contextLength: byId.contextLength,
          inputPerMillion: byId.inputPerMillion,
          outputPerMillion: byId.outputPerMillion,
          cachedInputPerMillion: byId.cachedInputPerMillion,
        );
      }
    }
    return null;
  }

  /// 预热：拉取或读缓存并建索引。失败（离线且无缓存）保持「未知」而不抛错——
  /// 模型照常能用，只是窗口与价格拿不到。
  Future<void> warmUp() async {
    if (warmed) return;
    try {
      final Map<String, List<ModelsDevModel>> catalog = await _client.fetch();
      _index(catalog);
      if (warmed && !_updates.isClosed) _updates.add(null);
    } on ModelsDevException {
      return;
    }
  }

  /// 强制刷新（忽略缓存）。
  Future<void> refresh() async {
    try {
      _index(await _client.fetch(force: true));
      if (!_updates.isClosed) _updates.add(null);
    } on ModelsDevException {
      return;
    }
  }

  void _index(Map<String, List<ModelsDevModel>> catalog) {
    _byProvider = <String, Map<String, ModelProfile>>{
      for (final MapEntry<String, List<ModelsDevModel>> entry
          in catalog.entries)
        entry.key: <String, ModelProfile>{
          for (final ModelsDevModel model in entry.value)
            model.id: ModelProfile(
              provider: entry.key,
              model: model.id,
              contextLength: model.contextLength,
              inputPerMillion: model.costInput,
              outputPerMillion: model.costOutput,
            ),
        },
    };
  }

  /// 释放。
  void close() {
    _updates.close();
    _client.close();
  }
}
