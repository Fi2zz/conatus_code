/// config.toml 完全兼容 kimi-code-config.toml 格式的解析测试。
library;

import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  group('kimi-code-config 格式兼容', () {
    test('顶层字段 + 各表完整解析', () {
      final ConatusCodeConfig config = _load(_kimiToml());

      // 顶层
      expect(config.llm.defaultModel, 'volcengine-coding-plan/deepseek-v4-flash');
      expect(config.approval.mode, ApprovalMode.neverAsk); // yolo
      expect(config.defaultPlanMode, isTrue);
      expect(config.extraSkillDirs, <String>['/Users/fitz/.trae/skills']);
      expect(config.mergeAllSkills, isTrue);
      expect(config.telemetry, isFalse);

      // [models.*]
      expect(config.models, hasLength(4));
      final ModelConfig glm = config.models
          .firstWhere((ModelConfig m) => m.model == 'glm-5.3-flash');
      expect(glm.provider, 'opencode-go');
      expect(glm.displayName, 'GLM-5.3-Flash (2x usage)');
      expect(glm.maxContext, 1000000);
      expect(glm.capabilities,
          <String>['image_in', 'video_in', 'always_thinking', 'tool_use']);
      expect(glm.reasoningKey, 'reasoning_content');
      expect(glm.supportEfforts, <String>['low', 'high', 'max']);
      expect(glm.protocol, isEmpty);

      final ModelConfig m3 = config.models
          .firstWhere((ModelConfig m) => m.model == 'minimax-m3');
      expect(m3.protocol, 'anthropic');
      expect(m3.baseUrl, 'https://opencode.ai/zen/go');

      final ModelConfig k3 = config.models
          .firstWhere((ModelConfig m) => m.model == 'k3');
      expect(k3.defaultEffort, 'high');
      expect(k3.maxOutputSize, 0); // 未填
      expect(k3.provider, 'managed:kimi-code');

      // [providers.*]（含 oauth.storage）
      expect(config.providers, hasLength(2));
      final ProviderConfig kimi = config.providers
          .firstWhere((ProviderConfig p) => p.name == 'managed:kimi-code');
      expect(kimi.type, ProviderType.kimi);
      expect(kimi.oauthKey, 'oauth/kimi-code');
      expect(config.providers.firstWhere((ProviderConfig p) => p.name == 'deepseek').baseUrl,
          'https://api.deepseek.com/v1');

      // [thinking]
      expect(config.thinking.enabled, isTrue);
      expect(config.thinking.effort, 'high');

      // [services.*]（含 oauth）
      expect(config.services, hasLength(1));
      final ServiceConfig search = config.services.first;
      expect(search.name, 'moonshot_search');
      expect(search.baseUrl, 'https://api.kimi.com/coding/v1/search');
      expect(search.oauthKey, 'oauth/kimi-code');

      // [background] / [loop_control]
      expect(config.background.keepAliveOnExit, isFalse);
      expect(config.background.maxRunningTasks, 4);
      expect(config.loopControl.compactionTriggerRatio, 0.85);
      expect(config.loopControl.maxStepsPerTurn, 200);
    });

    test('顶层 default_model 优先于 [llm]；兼容旧格式', () {
      final ConatusCodeConfig top = _load('default_model = "a/m"\n');
      expect(top.llm.defaultModel, 'a/m');

      final ConatusCodeConfig legacy = _load('[llm]\ndefault_model = "b/m2"\n');
      expect(legacy.llm.defaultModel, 'b/m2');
    });

    test('permission 模式映射：bypassPermissions / acceptEdits / 非法', () {
      expect(_load('default_permission_mode = "bypassPermissions"\n').approval.mode,
          ApprovalMode.neverAsk);
      expect(_load('default_permission_mode = "acceptEdits"\n').approval.mode,
          ApprovalMode.askWhenNeeded);
      expect(_load('default_permission_mode = "default"\n').approval.mode,
          ApprovalMode.askWhenNeeded);
      expect(
        () => _load('default_permission_mode = "bogus"\n'),
        throwsA(isA<ConfigException>()),
      );
    });
  });
}

ConatusCodeConfig _load(String toml) {
  final Directory dir = Directory.systemTemp.createTempSync('nava-kimi-');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String path = '${dir.path}/config.toml';
  File(path).writeAsStringSync(toml);
  return loadConfig(path: path);
}

/// 覆盖全部表与字段的精简 kimi-code-config 样例。
String _kimiToml() => '''
default_model = "volcengine-coding-plan/deepseek-v4-flash"
default_permission_mode = "yolo"
default_plan_mode = true
extra_skill_dirs = [ "/Users/fitz/.trae/skills" ]
merge_all_available_skills = true
telemetry = false

[background]
keep_alive_on_exit = false
max_running_tasks = 4

[loop_control]
compaction_trigger_ratio = 0.85
max_steps_per_turn = 200
reserved_context_size = 50000

[models."opencode-go/glm-5.3-flash"]
capabilities = [ "image_in", "video_in", "always_thinking", "tool_use" ]
display_name = "GLM-5.3-Flash (2x usage)"
max_context_size = 1000000
model = "glm-5.3-flash"
provider = "opencode-go"
reasoning_key = "reasoning_content"
support_efforts = [ "low", "high", "max" ]

[models."opencode-go/minimax-m3"]
base_url = "https://opencode.ai/zen/go"
capabilities = [ "image_in", "video_in", "thinking", "tool_use" ]
display_name = "MiniMax-M3"
max_context_size = 1000000
model = "minimax-m3"
protocol = "anthropic"
provider = "opencode-go"

[models."kimi-code/k3"]
capabilities = [ "thinking", "always_thinking", "image_in", "video_in", "tool_use", "dynamically_loaded_tools" ]
default_effort = "high"
display_name = "K3"
max_context_size = 1048576
model = "k3"
provider = "managed:kimi-code"
support_efforts = [ "low", "high", "max" ]

[models."volcengine-coding-plan/doubao-seed-2.1-turbo"]
provider = "volcengine-coding-plan"
model = "doubao-seed-2.1-turbo"
max_context_size = 256000
max_output_size = 256000
capabilities = [ "image_in", "video_in", "thinking", "tool_use" ]
display_name = "Seed 2.1 Turbo"
reasoning_key = "reasoning_content"
support_efforts = [ "low", "high" ]
off_effort = "none"

[providers.deepseek]
api_key = "sk-"
base_url = "https://api.deepseek.com/v1"
type = "openai"

[providers."managed:kimi-code"]
api_key = ""
base_url = "https://api.kimi.com/coding/v1"
type = "kimi"

[providers."managed:kimi-code".oauth]
key = "oauth/kimi-code"
storage = "file"

[services.moonshot_search]
api_key = ""
base_url = "https://api.kimi.com/coding/v1/search"

[services.moonshot_search.oauth]
key = "oauth/kimi-code"
storage = "file"

[thinking]
effort = "high"
enabled = true
''';
