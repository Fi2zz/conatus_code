/// 装配入口：配置 + 项目发现 → 信任 → 启动宿主。
library;

import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';

import '../config/config_schema.dart';
import 'plugin_config.dart';
import 'plugin_discovery.dart';
import 'plugin_entry.dart';
import 'plugin_service.dart';
import 'plugin_trust.dart';
import 'plugin_types.dart';

/// 把配置插件与项目插件合并成候选，完成审批后启动宿主。
class PluginAssembly {
  const PluginAssembly._();

  /// 装配；无插件时返回 no-op 服务。
  static Future<PluginService> assemble({
    required List<PluginConfig> plugins,
    required String workdir,
    required String baseDir,
    required ToolRegistry tools,
    required bool interactive,
    bool trustProjectPlugins = false,
    PluginTrustPrompter? prompter,
    String? configPath,
    String? homeDir,
    void Function(String message)? warn,
  }) async {
    final void Function(String) log = warn ?? ((String message) {});
    final List<PluginCandidate> candidates = <PluginCandidate>[];
    final List<PluginCandidate> projectCandidates = <PluginCandidate>[];
    final String configBase = configPath == null
        ? Directory.current.path
        : File(configPath).parent.path;
    for (final PluginConfig config in plugins) {
      if (!config.enabled) continue;
      if (isLocalPluginSource(config.source)) {
        final String path = resolveLocalPluginSource(
          config.source,
          base: configBase,
        );
        try {
          candidates.add(localPluginCandidate(path, options: config.options));
        } on FileSystemException {
          log('插件入口不存在：$path');
        }
      } else {
        candidates.add(
          PluginCandidate(
            spec: PluginSpec(
              id: pluginIdFor(config.source),
              source: config.source,
              options: config.options,
            ),
            origin: 'config',
            entry: config.source,
            fingerprint: config.source,
            local: false,
          ),
        );
      }
    }
    final PluginDiscoveryResult project = await PluginDiscovery(
      workdir: workdir,
    ).discoverProject();
    for (final String warning in project.warnings) {
      log(warning);
    }
    projectCandidates.addAll(project.candidates);
    final PluginTrustStore trust = PluginTrustStore(
      path: '$baseDir${Platform.pathSeparator}plugin-trust.json',
      prompter: interactive ? (prompter ?? stdinPluginTrustPrompter) : null,
      autoTrust: trustProjectPlugins,
      autoDeny: !interactive && !trustProjectPlugins,
    );
    final List<PluginCandidate> trusted = await trust.filter(projectCandidates);
    final String home =
        homeDir ?? Platform.environment['HOME'] ?? Directory.current.path;
    return PluginService.start(
      candidates: <PluginCandidate>[...candidates, ...trusted],
      workdir: workdir,
      homeDir: home,
      tools: tools,
      warn: log,
    );
  }
}
