/// 设置面板：分页列表 + 选中项，选中后跳转到对应的既有命令面板。
library;

/// 每页条目数。
const int kSettingsPageSize = 5;

/// 一条设置项。
class SettingsItem {
  const SettingsItem({
    required this.title,
    required this.description,
    required this.command,
  });

  /// 展示标题（与命令同名，便于对照）。
  final String title;

  /// 一行说明。
  final String description;

  /// 选中后执行的斜杠命令。
  final String command;
}

/// 全部设置项（两页）。
const List<SettingsItem> kSettingsItems = <SettingsItem>[
  SettingsItem(
    title: 'Model',
    description: '切换当前模型与思考强度。',
    command: '/model',
  ),
  SettingsItem(
    title: 'Permission',
    description: '设置工具调用的审批方式。',
    command: '/permission',
  ),
  SettingsItem(
    title: 'Theme',
    description: '切换终端配色主题。',
    command: '/theme',
  ),
  SettingsItem(
    title: 'Agent',
    description: '选择新会话的默认 Agent。',
    command: '/agents',
  ),
  SettingsItem(
    title: 'Plan Mode',
    description: '进入 / 退出先规划后执行的 Plan Mode。',
    command: '/plan',
  ),
  SettingsItem(
    title: 'Provider',
    description: '管理模型提供商与凭据。',
    command: '/provider',
  ),
  SettingsItem(
    title: 'LSP',
    description: '查看 LSP 诊断与服务器状态。',
    command: '/lsp',
  ),
  SettingsItem(
    title: 'Story',
    description: '人机双写故事层：审阅待定补丁。',
    command: '/story',
  ),
  SettingsItem(
    title: 'Keybinds',
    description: '查看当前键位绑定与冲突。',
    command: '/keybinds',
  ),
  SettingsItem(
    title: 'Doctor',
    description: '体检配置、工具与 MCP。',
    command: '/doctor',
  ),
];

/// 设置面板状态。
class SettingsPrompt {
  SettingsPrompt({this.onChanged});

  /// 状态变化回调（组件据此重绘）。
  void Function()? onChanged;

  bool _open = false;
  int _index = 0;

  /// 面板是否可见。
  bool get open => _open;

  /// 当前选中下标（全局）。
  int get index => _index;

  /// 当前选中项。
  SettingsItem get selected => kSettingsItems[_index];

  /// 总页数。
  int get pageCount =>
      (kSettingsItems.length + kSettingsPageSize - 1) ~/ kSettingsPageSize;

  /// 当前页（从 1 起）。
  int get page => _index ~/ kSettingsPageSize + 1;

  /// 当前页的条目。
  List<SettingsItem> get pageItems {
    final int start = (_index ~/ kSettingsPageSize) * kSettingsPageSize;
    final int end = (start + kSettingsPageSize).clamp(0, kSettingsItems.length);
    return kSettingsItems.sublist(start, end);
  }

  /// 打开面板（从第一项开始）。
  void openPanel() {
    _index = 0;
    _open = true;
    onChanged?.call();
  }

  /// 关闭面板。
  void close() {
    if (!_open) return;
    _open = false;
    onChanged?.call();
  }

  /// 上下移动（越界钳制）。
  void move(int delta) {
    final int next = _index + delta;
    _index = next < 0 ? 0 : (next >= kSettingsItems.length ? kSettingsItems.length - 1 : next);
    onChanged?.call();
  }

  /// 左右翻页（保留页内相对位置）。
  void pageBy(int delta) {
    final int target = (page - 1 + delta).clamp(0, pageCount - 1);
    final int inPage = _index % kSettingsPageSize;
    final int base = target * kSettingsPageSize;
    final int maxInPage =
        (kSettingsItems.length - base).clamp(0, kSettingsPageSize) - 1;
    _index = base + (inPage > maxInPage ? maxInPage : inPage);
    onChanged?.call();
  }
}
