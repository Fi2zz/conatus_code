import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  group('appendProviderSection', () {
    test('追加裸键 provider 段，保留既有内容', () {
      const String toml = '[llm]\ndefault_model = "a/m"\n';

      final String result = appendProviderSection(
        toml,
        name: 'ark',
        baseUrl: 'https://ark.example/v3',
        apiKey: 'sk-1',
        type: 'openai',
      );

      expect(result, startsWith(toml));
      expect(result, contains('[providers.ark]'));
      expect(result, contains('api_key = "sk-1"'));
      expect(result, contains('base_url = "https://ark.example/v3"'));
      expect(result, contains('type = "openai"'));
    });

    test('名字含 : 时加引号；api_key 为空时省略该行', () {
      final String result = appendProviderSection(
        '',
        name: 'managed:kimi-code',
        baseUrl: 'https://api.kimi.com/coding/v1',
        apiKey: '',
        type: 'kimi',
      );

      expect(result, contains('[providers."managed:kimi-code"]'));
      expect(result, isNot(contains('api_key')));
      expect(result, contains('type = "kimi"'));
    });
  });

  group('upsertDefaultModel', () {
    test('已有非注释行 → 替换', () {
      const String toml = '[llm]\ndefault_model = "old/m"\n\n[agent]\n';

      final String result = upsertDefaultModel(toml, 'new/m2');

      expect(result, contains('default_model = "new/m2"'));
      expect(result, isNot(contains('old/m')));
      expect(result, contains('[agent]'));
    });

    test('只有注释行 → 在 [llm] 段首行后插入，注释保留', () {
      const String toml = '[llm]\n# default_model = "provider/model"\n\n[agent]\n';

      final String result = upsertDefaultModel(toml, 'ark/m');

      expect(result, contains('# default_model = "provider/model"'));
      expect(result, contains('default_model = "ark/m"'));
      // 插入位置在 [llm] 之后、注释之前
      final int section = result.indexOf('[llm]');
      final int inserted = result.indexOf('default_model = "ark/m"');
      expect(inserted, greaterThan(section));
      expect(inserted, lessThan(result.indexOf('# default_model')));
    });

    test('无 [llm] 段 → 追加该段', () {
      const String toml = '[agent]\nmax_steps = 8\n';

      final String result = upsertDefaultModel(toml, 'ark/m');

      expect(result, startsWith(toml));
      expect(result, contains('[llm]'));
      expect(result, contains('default_model = "ark/m"'));
    });
  });

  group('deriveProviderName', () {
    test('标准 api 域名取 host 倒数第二段', () {
      expect(deriveProviderName('https://api.deepseek.com/v1'), 'deepseek');
      expect(deriveProviderName('https://api.kimi.com/coding/v1'), 'kimi');
    });

    test('无协议 / 非法 URL 回退 custom', () {
      expect(deriveProviderName(''), 'custom');
      expect(deriveProviderName('not a url'), 'custom');
    });

    test('单段 host 直接用 host', () {
      expect(deriveProviderName('http://localhost:11434/v1'), 'localhost');
    });
  });

  test('writeConfigFile 写入并创建父目录', () {
    final Directory dir = Directory.systemTemp.createTempSync('nava-writer-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String path = '${dir.path}/nested/config.toml';

    writeConfigFile(path, '[llm]\n');

    expect(File(path).readAsStringSync(), '[llm]\n');
  });
}
