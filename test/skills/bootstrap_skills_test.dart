/// 启动技能注入：把指定技能正文挂成常驻 system prompt 段。
library;

import 'package:conatus_code/src/skills/bootstrap_skills.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_skill/conatus_skill.dart';
import 'package:test/test.dart';

SkillRegistry _registry() =>
    SkillRegistry(refreshDebounce: const Duration(milliseconds: 5));

void _register(
  SkillRegistry registry,
  String name, {
  String content = '技能正文',
  String description = '测试技能。',
  SkillResourceBase? resourceBase,
}) {
  registry.register(
    SkillRegistration(
      name: name,
      description: description,
      content: content,
      resourceBase: resourceBase,
    ),
  );
}

void main() {
  group('renderSkillBootstrap', () {
    test('包装完整正文并追加 nava 映射', () {
      const SkillDefinition definition = SkillDefinition(
        summary: SkillSummary(
          name: 'using-superpowers',
          description: '启动',
          source: kSkillSourceRuntime,
          provider: kSkillRuntimeProvider,
        ),
        content: '先检查技能。',
      );

      final String text = renderSkillBootstrap(<SkillDefinition>[
        definition,
      ], appendix: 'MAPPING');

      expect(text, startsWith('<EXTREMELY_IMPORTANT>\n'));
      expect(text, contains('You have superpowers.'));
      expect(text, contains('using-superpowers'));
      expect(text, contains('ALREADY LOADED'));
      expect(text, contains('先检查技能。'));
      expect(text, contains('MAPPING'));
      expect(text, endsWith('</EXTREMELY_IMPORTANT>'));
    });

    test('多个技能按传入顺序拼接', () {
      const SkillDefinition first = SkillDefinition(
        summary: SkillSummary(
          name: 'first',
          description: '一',
          source: kSkillSourceRuntime,
          provider: kSkillRuntimeProvider,
        ),
        content: '第一段',
      );
      const SkillDefinition second = SkillDefinition(
        summary: SkillSummary(
          name: 'second',
          description: '二',
          source: kSkillSourceRuntime,
          provider: kSkillRuntimeProvider,
        ),
        content: '第二段',
      );

      final String text = renderSkillBootstrap(<SkillDefinition>[
        first,
        second,
      ]);

      expect(text.indexOf('第一段'), lessThan(text.indexOf('第二段')));
      expect(text, contains('first, second'));
    });
  });

  group('SkillBootstrapSection', () {
    test('start 加载技能并注册常驻段', () async {
      final SkillRegistry registry = _registry();
      addTearDown(registry.dispose);
      _register(registry, 'using-superpowers', content: '必须在行动前检查技能。');
      await registry.refresh();
      final SystemPrompt prompt = SystemPrompt();
      final SkillBootstrapSection section = SkillBootstrapSection(
        registry: registry,
        prompt: prompt,
        names: const <String>['using-superpowers'],
        appendix: 'MAPPING',
      );
      addTearDown(section.dispose);

      await section.start();

      expect(prompt.sections.map((PromptSection s) => s.name), <String>[
        kSkillBootstrapSectionName,
      ]);
      expect(prompt.sections.single.order, kSkillBootstrapOrder);
      expect(prompt.render(prompt.assemble()), contains('必须在行动前检查技能。'));
      expect(prompt.render(prompt.assemble()), contains('MAPPING'));
    });

    test('缺失技能不注册空段', () async {
      final SkillRegistry registry = _registry();
      addTearDown(registry.dispose);
      final SystemPrompt prompt = SystemPrompt();
      final SkillBootstrapSection section = SkillBootstrapSection(
        registry: registry,
        prompt: prompt,
        names: const <String>['missing'],
      );
      addTearDown(section.dispose);

      await section.start();

      expect(prompt.sections, isEmpty);
    });

    test('注册表出现目标技能后自动挂段', () async {
      final SkillRegistry registry = _registry();
      addTearDown(registry.dispose);
      final SystemPrompt prompt = SystemPrompt();
      final SkillBootstrapSection section = SkillBootstrapSection(
        registry: registry,
        prompt: prompt,
        names: const <String>['late'],
      );
      addTearDown(section.dispose);
      await section.start();
      expect(prompt.sections, isEmpty);

      _register(registry, 'late', content: '后来居上。');
      await registry.refresh();
      await section.refresh();

      expect(prompt.render(prompt.assemble()), contains('后来居上。'));
    });

    test('dispose 撤销常驻段', () async {
      final SkillRegistry registry = _registry();
      addTearDown(registry.dispose);
      _register(registry, 'using-superpowers', content: '正文');
      await registry.refresh();
      final SystemPrompt prompt = SystemPrompt();
      final SkillBootstrapSection section = SkillBootstrapSection(
        registry: registry,
        prompt: prompt,
        names: const <String>['using-superpowers'],
      );
      await section.start();
      expect(prompt.sections, isNotEmpty);

      section.dispose();

      expect(prompt.sections, isEmpty);
    });
  });
}
