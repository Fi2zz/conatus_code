/// 把插件声明的工具接进 nava 的 ToolRegistry。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

/// 插件工具：参数 schema 由插件提供（任意 JSON Schema），执行交给宿主。
class PluginTool extends Tool {
  PluginTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
    ToolRisk riskLevel = ToolRisk.high,
  }) : _risk = riskLevel;

  @override
  final String name;

  @override
  final String description;

  /// 插件给出的 JSON Schema。
  final Map<String, Object?> parameters;

  /// 执行体：参数 → 文本。
  final Future<String> Function(Map<String, Object?> arguments, String callId)
  execute;

  final ToolRisk _risk;

  @override
  ToolRisk get riskLevel => _risk;

  @override
  Duration get timeout => const Duration(seconds: 60);

  @override
  Map<String, Object?> toSchema() => <String, Object?>{
    'name': name,
    'description': description,
    'parameters': parameters,
  };

  @override
  Future<ToolResult> call(ToolContext context) async {
    try {
      final String output = await execute(context.arguments, context.callId);
      return ToolResult.success(output);
    } on Object catch (error) {
      return ToolResult.failure(
        '插件工具失败：$error',
        error: ToolError('PLUGIN_TOOL_ERROR', '$error'),
      );
    }
  }
}
