/// provider 管理浮层状态：展示 config 配置的提供商 + 新增入口。
///
/// 只持有屏上状态；数据源是 config.toml，新增写回文件（见 `tui_controller.dart`）。
library;

import 'dart:async';

/// 列表里的一项。
class TuiProviderItem {
  const TuiProviderItem({
    required this.name,
    required this.baseUrl,
    required this.current,
    this.isAdd = false,
    this.isCustom = false,
    this.isKnown = false,
  });

  /// 提供商名；[isAdd] 为 true 时是「[ Add New Platform ]」占位项，
  /// [isCustom] 为 true 时是「自定义来源」项，[isKnown] 为 true 时是
  /// 「知名第三方来源」入口项。
  final String name;

  /// 端点地址（列表第二行灰字）。
  final String baseUrl;

  /// 是否为当前选中的提供商（渲染 `← 当前`）。
  final bool current;

  /// 是否为新增入口项。
  final bool isAdd;

  /// 是否为「自定义 provider」来源项（只填 base_url / api_key / model）。
  final bool isCustom;

  /// 是否为「知名第三方 provider」来源入口项（进入后列出全部预设）。
  final bool isKnown;

  /// 列表展示名。
  String get label {
    if (isAdd) {
      return '[ Add New Platform ]';
    }
    if (isCustom) {
      return name.isEmpty ? '[ custom ]' : name;
    }
    return name;
  }
}

/// provider 浮层状态。
class TuiProviderPrompt {
  TuiProviderPrompt({this.onChanged});

  /// 状态变化回调（组件据此重绘）。
  void Function()? onChanged;

  List<TuiProviderItem> _items = const <TuiProviderItem>[];
  int _index = 0;
  bool _open = false;
  String _title = 'Providers';
  String _hint = '↑↓ 选择 · Enter 切换 / 新增 · Esc 取消';
  Completer<TuiProviderItem?>? _pending;

  /// 浮层是否可见。
  bool get open => _open;

  /// 面板标题（管理面板 `Providers`，新增来源面板 `Add provider`）。
  String get title => _title;

  /// 面板按键提示行。
  String get hint => _hint;

  /// 是否有待收口的选择请求（[choose] 发起的）。
  bool get awaiting => _pending != null;

  /// 列表项。
  List<TuiProviderItem> get items => _items;

  /// 当前选中下标。
  int get index => _index;

  /// 当前选中项；无列表返回 `null`。
  TuiProviderItem? get selected => _items.isEmpty ? null : _items[_index];

  /// 打开并载入列表（默认选中当前提供商）。
  void show(List<TuiProviderItem> items, {String? title, String? hint}) {
    _items = items;
    _title = title ?? 'Providers';
    _hint = hint ?? '↑↓ 选择 · Enter 切换 / 新增 · Esc 取消';
    _open = true;
    final int current =
        items.indexWhere((TuiProviderItem item) => item.current);
    _index = current < 0 ? 0 : current;
    onChanged?.call();
  }

  /// 选择模式：打开面板并等待用户选中（Enter）或取消（Esc）。
  ///
  /// 面板关闭前调用方等待返回；取消返回 `null`。
  Future<TuiProviderItem?> choose(
    List<TuiProviderItem> items, {
    String? title,
    String? hint,
  }) {
    final Completer<TuiProviderItem?> completer = Completer<TuiProviderItem?>();
    _pending = completer;
    show(items, title: title, hint: hint);
    return completer.future;
  }

  /// 确认当前选中项并关闭（Enter）。
  void confirm() {
    final Completer<TuiProviderItem?>? pending = _pending;
    final TuiProviderItem? item = selected;
    close();
    if (pending != null && !pending.isCompleted) {
      pending.complete(item);
    }
  }

  /// 取消选择并关闭（Esc）。
  void cancel() {
    final Completer<TuiProviderItem?>? pending = _pending;
    close();
    if (pending != null && !pending.isCompleted) {
      pending.complete(null);
    }
  }

  /// 刷新列表（删除后保持下标有效）。
  void refresh(List<TuiProviderItem> items) {
    if (!_open) {
      return;
    }
    _items = items;
    if (_index >= items.length) {
      _index = items.isEmpty ? 0 : items.length - 1;
    }
    onChanged?.call();
  }

  /// 移动光标（越界钳制；空列表无操作）。
  void move(int delta) {
    if (_items.isEmpty) {
      return;
    }
    final int last = _items.length - 1;
    final int next = _index + delta;
    _index = next < 0 ? 0 : (next > last ? last : next);
    onChanged?.call();
  }

  /// 关闭面板。
  void close() {
    _open = false;
    _items = const <TuiProviderItem>[];
    _index = 0;
    onChanged?.call();
  }
}
