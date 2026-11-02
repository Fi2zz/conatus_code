/// 插件技能 → nava 运行时技能注册。
library;

import 'package:conatus_skill/conatus_skill.dart';

import 'plugin_types.dart';

/// `PluginInitResult.inlineSkills`：把插件技能转成运行时注册。
extension PluginInlineSkills on PluginInitResult {
  /// 可直接注册进 SkillRegistry 的内联技能。
  List<SkillRegistration> get inlineSkills => <SkillRegistration>[
    for (final PluginSkill skill in skills)
      if (isSkillName(skill.name))
        SkillRegistration(
          name: skill.name,
          description: skill.description,
          content: skill.content,
        ),
  ];
}
