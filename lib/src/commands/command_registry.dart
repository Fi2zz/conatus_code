/// 自定义命令发现与注册表。
///
/// 发现顺序由低到高：全局 OpenCode → 全局 nava → 项目 OpenCode → 项目
/// nava；同名命令后者覆盖前者。`.opencode` 只读：这里只 `exists` /
/// `list` / `readAsString`，不创建目录、不写缓存。
library;

import 'dart:io';

import 'command_definition.dart';
import 'command_parser.dart';

/// 命令注册表：解析后的命令按名称索引。
class CommandRegistry {
  CommandRegistry._();

  final Map<String, CommandDefinition> _definitions =
      <String, CommandDefinition>{};
  final List<String> _warnings = <String>[];

  /// 加载四层命令目录；目录缺失或单个文件损坏都不影响其余命令。
  static Future<CommandRegistry> load({
    required String workdir,
    String? home,
  }) async {
    final CommandRegistry registry = CommandRegistry._();
    for (final String root in _commandRoots(workdir: workdir, home: home)) {
      await registry._loadRoot(root);
    }
    return registry;
  }

  /// 全部命令，按名称稳定排序。
  List<CommandDefinition> get all {
    final List<CommandDefinition> commands = _definitions.values.toList(
      growable: false,
    );
    commands.sort(
      (CommandDefinition left, CommandDefinition right) =>
          left.name.compareTo(right.name),
    );
    return commands;
  }

  /// 加载期间跳过的文件说明；供 TUI 展开诊断。
  List<String> get warnings => List<String>.unmodifiable(_warnings);

  /// 精确名称查找；未命中返回 `null`。
  CommandDefinition? byName(String name) => _definitions[name];

  /// 注册或覆盖一条命令（动态命令、内置桥接用）。
  void add(CommandDefinition def) {
    if (def.name.trim().isEmpty) return;
    _definitions[def.name] = def;
  }

  Future<void> _loadRoot(String root) async {
    final Directory directory = Directory(root);
    if (!await directory.exists()) return;
    final List<String> files = <String>[];
    try {
      await for (final FileSystemEntity entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File && entity.path.toLowerCase().endsWith('.md')) {
          files.add(entity.path);
        }
      }
    } on FileSystemException catch (error) {
      _warnings.add('无法读取命令目录 $root: ${error.message}');
      return;
    }
    files.sort();
    for (final String file in files) {
      await _loadFile(root, file);
    }
  }

  Future<void> _loadFile(String root, String path) async {
    final String name = _commandName(root, path);
    final String text;
    try {
      text = await File(path).readAsString();
    } on FileSystemException catch (error) {
      _warnings.add('无法读取命令文件 $path: ${error.message}');
      return;
    }
    final CommandDefinition? def = parseCommandDocument(
      text,
      name: name,
      sourcePath: path,
    );
    if (def == null) {
      _warnings.add('跳过无效命令文件 $path');
      return;
    }
    _definitions[name] = def;
  }
}

/// 四层目录，低优先级在前。
List<String> _commandRoots({required String workdir, String? home}) {
  final List<String> roots = <String>[];
  final String? homeDir = _homeDirectory(home);
  if (homeDir != null) {
    roots.add('$homeDir/.config/opencode/commands');
    roots.add('$homeDir/.nava/commands');
  }
  roots.add('$workdir/.opencode/commands');
  roots.add('$workdir/.nava/commands');
  return roots;
}

/// `home` 显式值优先，其次 `HOME` / `USERPROFILE`；定位不到时只扫项目层。
String? _homeDirectory(String? home) {
  final String? explicit = _nonEmpty(home);
  if (explicit != null) return explicit;
  final Map<String, String> env = Platform.environment;
  return _nonEmpty(env['HOME']) ?? _nonEmpty(env['USERPROFILE']);
}

String? _nonEmpty(String? value) {
  final String? trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// 文件路径相对命令根目录 → 命令 ID（分隔符统一为 `/`，去掉 `.md`）。
String _commandName(String root, String path) {
  String relative = path.substring(root.length).replaceAll('\\', '/');
  while (relative.startsWith('/')) {
    relative = relative.substring(1);
  }
  return relative.toLowerCase().endsWith('.md')
      ? relative.substring(0, relative.length - 3)
      : relative;
}
