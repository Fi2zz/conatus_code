/// 可配置的全局键位表：动作常量、默认绑定、配置合成与冲突消解。
library;

import 'package:nocterm/nocterm.dart';

import 'key_binding.dart';

/// 全局动作 ID（`[keybinds]` 的键）。
abstract final class KeyActions {
  static const String exit = 'app.exit';
  static const String clear = 'app.clear';
  static const String help = 'help.show';
  static const String sessionNew = 'session.new';
  static const String sessionList = 'session.list';
  static const String modelList = 'model.list';
  static const String agentList = 'agent.list';
  static const String palette = 'command.palette';
  static const String theme = 'theme.switch';
  static const String tabNext = 'tab.next';
  static const String tabPrevious = 'tab.previous';
  static const String tabClose = 'tab.close';

  /// `/keybinds` 的展示顺序。
  static const List<String> ordered = <String>[
    exit,
    clear,
    help,
    sessionNew,
    sessionList,
    modelList,
    agentList,
    palette,
    theme,
    tabNext,
    tabPrevious,
    tabClose,
  ];

  /// 已知动作集合（未知 ID 只告警、不生效）。
  static const Set<String> known = <String>{...ordered};
}

/// 默认绑定；与改造前的硬编码键位保持一致。
const Map<String, String> kDefaultKeybinds = <String, String>{
  KeyActions.exit: 'ctrl+c,ctrl+d',
  KeyActions.clear: 'ctrl+l',
  KeyActions.help: 'f1',
  KeyActions.sessionNew: '<leader>n',
  KeyActions.sessionList: '<leader>l',
  KeyActions.modelList: '<leader>m',
  KeyActions.agentList: '<leader>a',
  KeyActions.palette: '<leader>p',
  KeyActions.theme: '<leader>t',
  KeyActions.tabNext: 'ctrl+tab',
  KeyActions.tabPrevious: 'ctrl+shift+tab',
  KeyActions.tabClose: '<leader>w',
  'leader': 'ctrl+x',
};

/// 合成后的键位表。
class Keymap {
  Keymap._(
    this.leader,
    this._direct,
    this._leaderActions,
    this._labels,
    this._warnings,
    this._conflicts,
  );

  /// 从 `[keybinds]` 配置合成；缺省动作沿用 [kDefaultKeybinds]。
  ///
  /// 配置显式声明的动作优先于默认值（可改键 / 抢占默认键）；同一按键被多个
  /// 动作声明时按声明顺序先到先得，其余进入 [conflicts]。
  static Keymap fromConfig(Map<String, String> config) {
    final _KeymapBuilder builder = _KeymapBuilder(
      config['leader'] ?? kDefaultKeybinds['leader']!,
    );
    for (final String action in _actionOrder(config)) {
      builder.add(action, config[action] ?? kDefaultKeybinds[action]!);
    }
    return builder.build();
  }

  /// leader 绑定；`null` 表示禁用（`none` / 非法值）。
  final KeyBinding? leader;

  final Map<KeyBinding, String> _direct;
  final Map<KeyBinding, String> _leaderActions;
  final Map<String, List<String>> _labels;
  final List<String> _warnings;
  final List<String> _conflicts;

  /// 单键动作（不含 `<leader>` 两段式）；未命中返回 `null`。
  String? actionFor(KeyboardEvent event) {
    for (final MapEntry<KeyBinding, String> entry in _direct.entries) {
      if (entry.key.matches(event)) return entry.value;
    }
    return null;
  }

  /// 该事件是否是 leader 前缀。
  bool isLeader(KeyboardEvent event) => leader?.matches(event) ?? false;

  /// leader 之后那一段对应的动作；未命中返回 `null`。
  String? actionForLeaderKey(KeyboardEvent event) {
    for (final MapEntry<KeyBinding, String> entry in _leaderActions.entries) {
      if (entry.key.matches(event)) return entry.value;
    }
    return null;
  }

  /// 动作当前的展示形式（`ctrl+c` / `<leader>m`）；未绑定为空列表。
  List<String> labelsFor(String action) =>
      List<String>.unmodifiable(_labels[action] ?? const <String>[]);

  /// 面向界面的展示形式：把 `<leader>x` 展开成 `ctrl+x 再 x`。
  ///
  /// `labelsFor` 保留配置里的原始写法，供解析与测试使用；界面提示用这个，
  /// 避免用户还要先理解 `<leader>` 是什么。
  List<String> displayLabelsFor(String action) {
    final String? leaderLabel = leader?.label;
    return <String>[
      for (final String label in labelsFor(action))
        if (leaderLabel != null && label.startsWith(kLeaderPrefix))
          '$leaderLabel 再 ${label.substring(kLeaderPrefix.length)}'
        else
          label,
    ];
  }

  /// 启动告警（未知动作 / 非法键位 / 冲突），按发现顺序。
  List<String> get warnings => List<String>.unmodifiable(_warnings);

  /// 按键冲突（先声明者生效）。
  List<String> get conflicts => List<String>.unmodifiable(_conflicts);
}

/// 配置声明顺序：显式动作在前，其余默认动作按默认顺序补齐。
List<String> _actionOrder(Map<String, String> config) => <String>[
  for (final String action in config.keys)
    if (action != 'leader') action,
  for (final String action in KeyActions.ordered)
    if (!config.containsKey(action)) action,
];

/// 逐动作累积绑定，集中处理冲突与告警。
class _KeymapBuilder {
  _KeymapBuilder(String leaderText) {
    leader = parseKeyBinding(leaderText);
    if (leader == null) {
      warnings.add('键位 leader "$leaderText" 无效，<leader> 快捷键已禁用。');
    }
  }

  KeyBinding? leader;
  final Map<KeyBinding, String> direct = <KeyBinding, String>{};
  final Map<KeyBinding, String> leaderActions = <KeyBinding, String>{};
  final Map<String, List<String>> labels = <String, List<String>>{};
  final List<String> warnings = <String>[];
  final List<String> conflicts = <String>[];

  void add(String action, String text) {
    if (!KeyActions.known.contains(action)) {
      warnings.add('未知键位动作 "$action"，已忽略。');
      return;
    }
    final List<String> bound = <String>[];
    labels[action] = bound;
    for (final String entry in text.split(',')) {
      _addOne(action, entry.trim(), bound);
    }
  }

  void _addOne(String action, String entry, List<String> bound) {
    if (entry.isEmpty || entry.toLowerCase() == 'none') return;
    final bool relative = entry.toLowerCase().startsWith(kLeaderPrefix);
    final KeyBinding? binding = parseKeyBinding(entry, leader: leader?.key);
    if (binding == null) {
      warnings.add('键位 "$entry"（$action）无法解析，已忽略。');
      return;
    }
    if (relative && leader == null) {
      warnings.add('键位 "$entry"（$action）依赖 leader，但 leader 不可用，已忽略。');
      return;
    }
    if (_bind(action, binding, relative: relative)) {
      bound.add(relative ? '$kLeaderPrefix${binding.label}' : binding.label);
    }
  }

  bool _bind(String action, KeyBinding binding, {required bool relative}) {
    if (!relative && leader == binding) {
      warnings.add('键位 "${binding.label}" 是 leader，不能直接绑定 $action，已忽略。');
      return false;
    }
    final Map<KeyBinding, String> table = relative ? leaderActions : direct;
    final String? owner = table[binding];
    if (owner != null) {
      final String label = relative
          ? '$kLeaderPrefix${binding.label}'
          : binding.label;
      final String conflict = '键位冲突 $label：$owner 已声明，忽略 $action。';
      warnings.add(conflict);
      conflicts.add(conflict);
      return false;
    }
    table[binding] = action;
    return true;
  }

  Keymap build() =>
      Keymap._(leader, direct, leaderActions, labels, warnings, conflicts);
}
