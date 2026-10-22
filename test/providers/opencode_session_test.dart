/// OpenCode Console / Go 网关的会话头与预设端点。
library;

import 'package:conatus_code/providers.dart';
import 'package:test/test.dart';

void main() {
  test('nava 会话 id 映射为 ses_ 前缀', () {
    expect(openCodeSessionId('session_abc'), 'ses_abc');
    expect(openCodeSessionId('abc'), 'ses_abc');
    expect(openCodeSessionId('ses_abc'), 'ses_abc');
  });

  test('仅 opencode.ai 主机视为 OpenCode 网关', () {
    expect(
      isOpenCodeBaseUrl('https://opencode.ai/inference/go/openai/v1'),
      isTrue,
    );
    expect(isOpenCodeBaseUrl('https://api.deepseek.com/v1'), isFalse);
    expect(isOpenCodeBaseUrl('not a url'), isFalse);
  });

  test('预设：Go 与 PAYG 端点正确', () {
    final Map<String, ProviderPreset> presets = <String, ProviderPreset>{
      for (final ProviderPreset p in kProviderPresets) p.id: p,
    };

    expect(
      presets['opencode-go']!.baseUrl,
      'https://opencode.ai/inference/go/openai/v1',
    );
    expect(
      presets['opencode-console']!.baseUrl,
      'https://opencode.ai/inference/openai/v1',
    );
    expect(presets['opencode-go-anthropic']!.type, 'anthropic');
    expect(
      presets['opencode-go-anthropic']!.baseUrl,
      'https://opencode.ai/inference/go/anthropic/v1',
    );
    expect(presets['opencode-go-anthropic']!.models, isNotEmpty);
  });
}
