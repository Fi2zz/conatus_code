/// 顶层 `[[tools]]` 的解析：声明式 CLI / HTTP 自定义工具。
library;

import 'package:conatus_foundation/conatus_foundation.dart'
    show ParamSpec, ToolRisk;

import 'config_schema.dart';
import 'config_values.dart';

const Set<String> _httpMethods = <String>{
  'GET',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
};

/// 解析 `[[tools]]`；非法即抛 [ConfigException]。
class ToolConfigParser extends ConfigValues {
  ToolConfigParser(super.raw, super.source);
  List<CustomToolConfig> parse() {
    final List<Map<String, dynamic>> tables = readTableList('tools');
    final Set<String> names = <String>{};
    return <CustomToolConfig>[
      for (int index = 0; index < tables.length; index++)
        _readTool(tables[index], index, names),
    ];
  }

  CustomToolConfig _readTool(
    Map<String, dynamic> table,
    int index,
    Set<String> names,
  ) {
    final String? name = readString(table, 'name');
    if (name == null) {
      throw ConfigException('$source：tools[$index].name 不能为空。');
    }
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_-]*$').hasMatch(name)) {
      throw ConfigException('$source：tools.$name 的名称只能含字母、数字、_、-。');
    }
    if (!names.add(name)) {
      throw ConfigException('$source：tools.$name 重复声明。');
    }
    final String? description = readString(table, 'description');
    if (description == null) {
      throw ConfigException('$source：tools.$name.description 不能为空。');
    }
    final String? command = readString(table, 'command');
    final String? url = readString(table, 'url');
    if ((command == null) == (url == null)) {
      throw ConfigException('$source：tools.$name 必须且只能声明 command 或 url 之一。');
    }
    final String method = (readString(table, 'method') ?? 'POST').toUpperCase();
    if (url != null) _validateUrl(url, name);
    if (!_httpMethods.contains(method)) {
      throw ConfigException('$source：tools.$name.method "$method" 不支持。');
    }
    return CustomToolConfig(
      name: name,
      description: description,
      command: command,
      args: readStringList(table, 'args'),
      url: url,
      method: method,
      headers: readStringMap(table, 'headers', 'tools.$name.headers'),
      env: readStringMap(table, 'env', 'tools.$name.env'),
      cwd: readString(table, 'cwd'),
      timeoutMs: readPositiveInt(table, 'timeout_ms', 30000),
      risk: _risk(readString(table, 'risk'), name),
      params: _params(table, name),
    );
  }

  ToolRisk _risk(String? raw, String name) => switch (raw) {
    null || 'high' => ToolRisk.high,
    'medium' => ToolRisk.medium,
    'low' => ToolRisk.low,
    _ => throw ConfigException('$source：tools.$name.risk 只能是 low / medium / high。'),
  };

  void _validateUrl(String url, String name) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ConfigException('$source：tools.$name.url 必须是 http(s) 地址。');
    }
  }

  List<ParamSpec> _params(Map<String, dynamic> table, String tool) {
    final Object? raw = table['params'];
    if (raw == null) return const <ParamSpec>[];
    if (raw is! List) {
      throw ConfigException('$source：tools.$tool.params 必须是表数组（[[tools.params]]）。');
    }
    final Set<String> names = <String>{};
    return <ParamSpec>[
      for (int index = 0; index < raw.length; index++)
        _readParam(raw[index], tool, index, names),
    ];
  }

  ParamSpec _readParam(
    Object? raw,
    String tool,
    int index,
    Set<String> names,
  ) {
    if (raw is! Map) {
      throw ConfigException('$source：tools.$tool.params[$index] 必须是表。');
    }
    final Map<String, dynamic> table = raw.cast<String, dynamic>();
    final String path = 'tools.$tool.params[$index]';
    final String? name = readString(table, 'name');
    if (name == null) {
      throw ConfigException('$source：$path.name 不能为空。');
    }
    if (!names.add(name)) {
      throw ConfigException('$source：tools.$tool.params 的 $name 重复。');
    }
    final String? type = readString(table, 'type');
    if (type == null) {
      throw ConfigException('$source：$path.type 不能为空。');
    }
    final String? description = readString(table, 'description');
    final bool required = readBool(table, 'required', false);
    final Object? fallback = table['default'];
    return switch (type) {
      'string' => ParamSpec.string(
        name,
        description: description,
        required: required,
        defaultValue: _default(table, fallback, String, path) as String?,
      ),
      'integer' => ParamSpec.integer(
        name,
        description: description,
        required: required,
        defaultValue: _default(table, fallback, int, path) as int?,
      ),
      'number' => ParamSpec.number(
        name,
        description: description,
        required: required,
        defaultValue: _default(table, fallback, num, path) as num?,
      ),
      'boolean' => ParamSpec.boolean(
        name,
        description: description,
        required: required,
        defaultValue: _default(table, fallback, bool, path) as bool?,
      ),
      'enum' || 'enumeration' => _enumParam(
        table,
        name,
        description,
        required,
        path,
      ),
      _ => throw ConfigException(
        '$source：$path.type "$type" 不支持（string / integer / number / boolean / enum）。',
      ),
    };
  }

  ParamSpec _enumParam(
    Map<String, dynamic> table,
    String name,
    String? description,
    bool required,
    String path,
  ) {
    final List<String> values = readStringList(table, 'values');
    if (values.isEmpty) {
      throw ConfigException('$source：$path.values 不能为空。');
    }
    final Object? fallback = table['default'];
    if (fallback != null && fallback is! String) {
      throw ConfigException('$source：$path.default 必须是字符串。');
    }
    if (fallback is String && !values.contains(fallback)) {
      throw ConfigException('$source：$path.default 必须是 values 之一。');
    }
    return ParamSpec.enumeration(
      name,
      values,
      description: description,
      required: required,
      defaultValue: fallback as String?,
    );
  }

  Object? _default(
    Map<String, dynamic> table,
    Object? fallback,
    Type type,
    String path,
  ) {
    if (fallback == null) return null;
    if (type == String && fallback is String) return fallback;
    if (type == int && fallback is int) return fallback;
    if (type == num && fallback is num) return fallback;
    if (type == bool && fallback is bool) return fallback;
    throw ConfigException('$source：$path.default 类型与 type 不匹配。');
  }
}
