/// models.dev 拉取器的解析 / 过滤 / 缓存行为。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_code/providers.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('keepForCoding', () {
    test('需同时支持工具调用与推理', () {
      expect(keepForCoding(true, true), isTrue);
      expect(keepForCoding(true, false), isFalse);
      expect(keepForCoding(false, true), isFalse);
      expect(keepForCoding(false, false), isFalse);
    });
  });

  group('ModelsDevClient', () {
    test('解析 + 编码过滤 + 能力映射', () async {
      final http.Client client = _fakeClient(_sampleJson());
      final ModelsDevClient fetcher = ModelsDevClient(client: client);
      final Map<String, List<ModelsDevModel>> catalog = await fetcher.fetch();
      fetcher.close();

      final List<ModelsDevModel> deepseek = catalog['deepseek']!;
      expect(deepseek, hasLength(2)); // 原始保留两条
      final List<ModelsDevModel> coding = <ModelsDevModel>[
        for (final ModelsDevModel model in deepseek)
          if (keepForCoding(model.toolCall, model.reasoning)) model,
      ];
      expect(coding, hasLength(1));

      final ModelSpec spec = coding.first.toSpec('deepseek');
      expect(spec.model, 'deepseek-chat');
      expect(spec.displayName, 'DeepSeek Chat');
      expect(spec.supportsImage, isTrue);
      expect(spec.maxContext, 1000000);
      expect(spec.inputPerMillion, 0.27);
      expect(spec.outputPerMillion, 1.1);
      expect(spec.capabilities, contains('tool_use'));
      expect(spec.capabilities, contains('always_thinking'));
      expect(spec.capabilities, contains('image_in'));
    });

    test('缓存命中时不再请求网络', () async {
      int calls = 0;
      final http.Client client = MockClient((http.Request request) async {
        calls++;
        return http.Response('{}', 200,
            headers: <String, String>{'content-type': 'application/json'});
      });
      final Directory dir = Directory.systemTemp.createTempSync('modelsdev-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final String cachePath = '${dir.path}/models.dev.json';

      final ModelsDevClient fetcher =
          ModelsDevClient(client: client, cachePath: cachePath);
      await fetcher.fetch();
      expect(File(cachePath).existsSync(), isTrue);
      await fetcher.fetch();
      fetcher.close();
      expect(calls, 1); // 仅首次下载，第二次读缓存
    });

    test('网络失败且无缓存 → 抛 ModelsDevException', () async {
      final http.Client client = MockClient((http.Request request) async {
        throw http.ClientException('offline');
      });
      final ModelsDevClient fetcher = ModelsDevClient(client: client);
      expect(fetcher.fetch(), throwsA(isA<ModelsDevException>()));
      fetcher.close();
    });
  });

  group('kProviderPresets', () {
    test('常见 provider 候选非空且带端点', () {
      expect(kProviderPresets, isNotEmpty);
      expect(kProviderPresets.every((ProviderPreset p) => p.baseUrl.isNotEmpty),
          isTrue);
      expect(kProviderPresets.any((ProviderPreset p) => p.id == 'deepseek'),
          isTrue);
    });
  });
}

http.Client _fakeClient(String body) =>
    MockClient((http.Request request) async => http.Response(
          body,
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ));

String _sampleJson() => jsonEncode(<String, dynamic>{
      'deepseek': <String, dynamic>{
        'name': 'DeepSeek',
        'models': <String, dynamic>{
          'deepseek-chat': <String, dynamic>{
            'id': 'deepseek-chat',
            'name': 'DeepSeek Chat',
            'tool_call': true,
            'reasoning': true,
            'attachment': true,
            'limit': <String, dynamic>{'context': 1000000, 'output': 8000},
            'cost': <String, dynamic>{'input': 0.27, 'output': 1.1},
            'modalities': <String, dynamic>{
              'input': <String>['text', 'image'],
              'output': <String>['text'],
            },
          },
          'pure-chat': <String, dynamic>{
            'id': 'pure-chat',
            'name': 'Pure Chat',
            'tool_call': false,
            'reasoning': false,
            'attachment': false,
            'limit': <String, dynamic>{'context': 128000, 'output': 4000},
            'cost': <String, dynamic>{'input': 0.1, 'output': 0.2},
            'modalities': <String, dynamic>{
              'input': <String>['text'],
              'output': <String>['text'],
            },
          },
        },
      },
    });
