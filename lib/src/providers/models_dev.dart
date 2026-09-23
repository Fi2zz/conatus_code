/// models.dev/api.json 的运行时拉取与解析。
///
/// 模型目录不内置：`/provider add` 选「已注册 provider」后从这里拉取该
/// provider 的模型清单（本地缓存 24h，离线时用缓存；无缓存则明确报错，
/// 不静默失败）。数据来源 OpenRouter 的 models.dev，非计费口径。
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'model_catalog.dart';

/// 模型是否适合编码：同时支持工具调用与推理（缺一不可）。
///
/// models.dev 的 `reasoning` / `tool_call` 是模型级能力标记；过滤掉不支持
/// 的模型，避免在 `/provider add` 的模型清单里混入纯聊天 / 纯推理模型。
bool keepForCoding(bool toolCall, bool reasoning) => toolCall && reasoning;

/// models.dev 上一个模型的原始字段（过滤与转 [ModelSpec] 用）。
class ModelsDevModel {
  const ModelsDevModel({
    required this.id,
    required this.name,
    required this.toolCall,
    required this.reasoning,
    required this.attachment,
    required this.contextLength,
    required this.costInput,
    required this.costOutput,
    required this.inputModalities,
  });

  /// 模型 id。
  final String id;

  /// 展示名。
  final String name;

  /// 是否支持工具调用。
  final bool toolCall;

  /// 是否支持推理。
  final bool reasoning;

  /// 是否支持附件（多模态输入）。
  final bool attachment;

  /// 上下文窗口（token）。
  final int contextLength;

  /// 每百万输入 token 成本（美元）。
  final double costInput;

  /// 每百万输出 token 成本（美元）。
  final double costOutput;

  /// 支持的输入模态（`text` / `image` / `video` / `pdf` / `audio`）。
  final List<String> inputModalities;

  /// 是否支持图像输入。
  bool get supportsImage =>
      inputModalities.contains('image') || inputModalities.contains('pdf');

  /// 转成统一的 [ModelSpec]（能力映射 OpenCode 风格）。
  ModelSpec toSpec(String provider) => ModelSpec(
        provider: provider,
        model: id,
        displayName: name,
        maxContext: contextLength,
        inputPerMillion: costInput,
        outputPerMillion: costOutput,
        capabilities: <String>{
          if (toolCall) ModelCapability.toolUse,
          if (reasoning) ModelCapability.alwaysThinking,
          if (supportsImage) ModelCapability.imageIn,
          if (inputModalities.contains('video')) ModelCapability.videoIn,
          if (inputModalities.contains('pdf')) ModelCapability.pdfIn,
          if (inputModalities.contains('audio')) ModelCapability.audioIn,
        },
      );
}

/// models.dev 拉取失败（网络不可达 / 缓存缺失 / 数据不合法）。
class ModelsDevException implements Exception {
  const ModelsDevException(this.message);

  /// 面向用户的说明。
  final String message;

  @override
  String toString() => 'ModelsDevException: $message';
}

/// models.dev 的运行时拉取器（带本地缓存）。
///
/// 每次拉取整份 api.json（较大）写缓存，后续会话优先读缓存；[force] 强制
/// 刷新。解析失败或网络不可达且无缓存时抛 [ModelsDevException]（fail-closed）。
class ModelsDevClient {
  ModelsDevClient({http.Client? client, String? cachePath})
      : _client = client ?? http.Client(),
        _cachePath = cachePath;

  /// models.dev 数据源。
  static const String kEndpoint = 'https://models.dev/api.json';

  /// 缓存有效期。
  static const Duration kCacheTtl = Duration(hours: 24);

  final http.Client _client;
  final String? _cachePath;

  /// 拉取（或读缓存）并解析，返回 providerId → 模型清单。
  ///
  /// [force] 为 true 时忽略缓存重新下载。
  Future<Map<String, List<ModelsDevModel>>> fetch({bool force = false}) async {
    final String raw;
    if (!force) {
      final String? cached = _readCache();
      if (cached != null) {
        return _parseRaw(cached);
      }
    }
    raw = await _download();
    _writeCache(raw);
    return _parseRaw(raw);
  }

  Future<String> _download() async {
    final http.Response response;
    try {
      response = await _client
          .get(Uri.parse(kEndpoint))
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw const ModelsDevException('无法连接 models.dev（$kEndpoint）。'
          '请检查网络，或改用 custom 手填 base_url。');
    }
    if (response.statusCode != 200) {
      throw ModelsDevException('models.dev 返回 HTTP ${response.statusCode}。');
    }
    return response.body;
  }

  Map<String, List<ModelsDevModel>> _parseRaw(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const ModelsDevException('models.dev 数据不是合法 JSON。');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ModelsDevException('models.dev 数据格式不合法。');
    }
    final Map<String, List<ModelsDevModel>> result =
        <String, List<ModelsDevModel>>{};
    for (final MapEntry<String, dynamic> entry in decoded.entries) {
      final Object? value = entry.value;
      if (value is Map<String, dynamic>) {
        result[entry.key] = _parseProvider(value);
      }
    }
    return result;
  }

  List<ModelsDevModel> _parseProvider(Map<String, dynamic> provider) {
    final Object? models = provider['models'];
    if (models is! Map) {
      return const <ModelsDevModel>[];
    }
    return <ModelsDevModel>[
      for (final Object? value in models.values)
        if (value is Map<dynamic, dynamic>) _parseModel(value),
    ];
  }

  ModelsDevModel _parseModel(Map<dynamic, dynamic> raw) {
    final String id = _stringOf(raw, 'id');
    return ModelsDevModel(
      id: id,
      name: _stringOf(raw, 'name'),
      toolCall: _boolOf(raw, 'tool_call'),
      reasoning: _boolOf(raw, 'reasoning'),
      attachment: _boolOf(raw, 'attachment'),
      contextLength: _intOf(raw['limit'], 'context'),
      costInput: _doubleOf(raw['cost'], 'input'),
      costOutput: _doubleOf(raw['cost'], 'output'),
      inputModalities: _inputModalities(raw['modalities']),
    );
  }

  static String _stringOf(Map<dynamic, dynamic> table, String key) {
    final Object? value = table[key];
    return value is String ? value : '';
  }

  static bool _boolOf(Map<dynamic, dynamic> table, String key) {
    final Object? value = table[key];
    return value is bool && value;
  }

  static int _intOf(Object? container, String key) {
    if (container is! Map) {
      return 0;
    }
    final Object? value = container[key];
    return value is num ? value.toInt() : 0;
  }

  static double _doubleOf(Object? container, String key) {
    if (container is! Map) {
      return 0;
    }
    final Object? value = container[key];
    return value is num ? value.toDouble() : 0;
  }

  static List<String> _inputModalities(Object? modalities) {
    if (modalities is! Map) {
      return const <String>[];
    }
    final Object? input = modalities['input'];
    if (input is! List) {
      return const <String>[];
    }
    return <String>[
      for (final Object? item in input)
        if (item is String) item,
    ];
  }

  String? _readCache() {
    final String? path = _cachePath;
    if (path == null) {
      return null;
    }
    final File file = File(path);
    if (!file.existsSync()) {
      return null;
    }
    final DateTime modified = file.lastModifiedSync();
    if (DateTime.now().difference(modified) > kCacheTtl) {
      return null;
    }
    return file.readAsStringSync();
  }

  void _writeCache(String raw) {
    final String? path = _cachePath;
    if (path == null) {
      return;
    }
    final File file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(raw);
  }

  /// 释放底层 HTTP 连接（调用方在不再需要时调用）。
  void close() => _client.close();
}
