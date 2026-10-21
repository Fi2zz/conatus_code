/// XERJ 代码检索工具：`code_search` / `find_definition` / `index_project`。
///
/// 只读检索与索引构建；节点起不来时返回 [ToolError] 让模型退回 `rg`。
library;

import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';

import 'xerj_exec.dart';

/// 按自然语言或关键词检索代码定义与片段。
class CodeSearchTool extends Tool {
  const CodeSearchTool(this._exec, {this.defaultLimit = 5});

  final XerjExec _exec;

  /// 默认返回条数。
  final int defaultLimit;

  @override
  String get name => 'code_search';

  @override
  String get description =>
      '在已索引的项目里检索代码定义与片段（XERJ，定义优先）。返回 file:line + 片段，'
      '比 rg 更省上下文。首次使用前先调用 index_project；结果为空或返回未索引时再退回 rg。';

  @override
  List<ParamSpec> get params => <ParamSpec>[
    ParamSpec.string('query', required: true, description: '要找什么，用自然语言或关键词'),
    ParamSpec.integer('limit', description: '返回条数，默认 $defaultLimit'),
  ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String query = ctx.str('query').trim();
    if (query.isEmpty || query.startsWith('-')) {
      return _invalid('query 不能为空或以 - 开头');
    }
    return _exec.search(query, limit: _limit(ctx, defaultLimit));
  }
}

/// 精确符号定位：这个符号定义在哪、签名是什么。
class FindDefinitionTool extends Tool {
  const FindDefinitionTool(this._exec, {this.defaultLimit = 5});

  final XerjExec _exec;

  /// 默认返回条数。
  final int defaultLimit;

  @override
  String get name => 'find_definition';

  @override
  String get description =>
      '已知符号名时精确定位定义（XERJ go-to-definition）：返回 file:line 与声明。'
      '适合确认“这个函数/类在哪定义、签名是什么”。';

  @override
  List<ParamSpec> get params => <ParamSpec>[
    ParamSpec.string('symbol', required: true, description: '符号名或能力描述'),
    ParamSpec.integer('limit', description: '返回条数，默认 $defaultLimit'),
    ParamSpec.string('language', description: '语言过滤，如 dart / rust / python'),
    ParamSpec.string('kind', description: '符号类型过滤，如 function / class / method'),
  ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String symbol = ctx.str('symbol').trim();
    if (symbol.isEmpty || symbol.startsWith('-')) {
      return _invalid('symbol 不能为空或以 - 开头');
    }
    return _exec.define(
      symbol,
      limit: _limit(ctx, defaultLimit),
      language: ctx.string('language'),
      kind: ctx.string('kind'),
    );
  }
}

/// 为一个目录建/刷新 XERJ 索引（幂等、可续跑）。
class IndexProjectTool extends Tool {
  IndexProjectTool(this._exec, {required String workdir, Duration? timeout})
    : _workdir = workdir,
      _timeout = timeout ?? const Duration(minutes: 10);

  final XerjExec _exec;
  final String _workdir;
  final Duration _timeout;

  @override
  String get name => 'index_project';

  @override
  String get description =>
      '为当前项目建立/刷新 XERJ 代码索引（幂等、可续跑）。大规模改动后调用一次，'
      '再用 code_search / find_definition 检索。返回 exit 3 表示部分文件被跳过，索引仍可用。';

  @override
  List<String> get pathParams => const <String>['path'];

  @override
  Duration? get timeout => _timeout;

  @override
  List<ParamSpec> get params => <ParamSpec>[
    ParamSpec.string('path', description: '要索引的目录，默认当前项目'),
  ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String path = ctx.string('path') ?? _workdir;
    final ToolResult result = await _exec.index(_absolute(path), _timeout);
    final Object? value = result.value;
    final bool junk = value is Map<String, Object?> && value['exitCode'] == 3;
    if (result.isError || !junk) return result;
    return ToolResult.success(
      '${result.content}\n（exit 3：部分文件被跳过，索引仍可用）',
      value: value,
    );
  }

  String _absolute(String path) {
    if (path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
      return path;
    }
    return '$_workdir${Platform.pathSeparator}$path';
  }
}

int _limit(ToolContext ctx, int fallback) {
  final int value = ctx.integer('limit') ?? fallback;
  if (value < 1) return 1;
  return value > 50 ? 50 : value;
}

ToolResult _invalid(String message) => ToolResult.failure(
  message,
  error: ToolError('XERJ_INVALID_QUERY', message),
);
