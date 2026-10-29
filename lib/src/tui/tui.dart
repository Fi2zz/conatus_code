/// nocterm TUI 主界面：顶栏 + 对话记录 + 输入栏 + 状态栏，斜杠命令见 `/help`。
///
/// 状态与命令由 [ConatusTuiController] 持有；本组件只做渲染与按键分派。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conatus_llm/conatus_llm.dart';
import 'package:nocterm/nocterm.dart';

import '../diff/tui_diff_view.dart';
import '../tabs/tab_bar.dart';
import 'agent_picker_view.dart';
import 'at_ref_menu.dart';
import 'at_ref_menu_view.dart';
import 'keymap/keymap.dart';
import 'keymap/keymap_dispatcher.dart';
import 'team_snapshot.dart';
import 'team_views.dart';
import 'theme/nava_theme.dart';
import 'theme/theme_view.dart';
import 'tui_attachment.dart';
import 'tui_choice.dart';
import 'tui_choice_view.dart';
import 'tui_chrome.dart';
import 'tui_clipboard_image.dart';
import 'tui_command_menu_view.dart';
import 'tui_commands.dart';
import 'tui_controller.dart';
import 'tui_copy.dart';
import 'tui_form.dart';
import 'tui_form_view.dart';
import 'tui_message.dart';
import 'tui_model.dart';
import 'tui_model_view.dart';
import 'tui_permission_prompt.dart';
import 'tui_permission_view.dart';
import 'tui_plan.dart';
import 'tui_plan_view.dart';
import 'tui_provider.dart';
import 'tui_provider_view.dart';
import 'tui_rename_view.dart';
import 'tui_session_picker_view.dart';
import 'tui_shell_mode.dart';
import 'tui_status_info.dart';
import 'tui_views.dart';

/// conatus TUI 根组件。
class AgentTui extends StatefulComponent {
  const AgentTui({super.key, required this.controller});

  /// 会话控制器（含屏上记录与斜杠命令状态）。
  final ConatusTuiController controller;

  @override
  State<AgentTui> createState() => _AgentTuiState();
}

class _AgentTuiState extends State<AgentTui> {
  late final ConatusTuiController _controller = component.controller;
  final TextEditingController _input = TextEditingController();
  final AutoScrollController _scroll = AutoScrollController();
  late final TuiCommandMenu _menu = TuiCommandMenu(
    commands: () => _controller.commands,
  );
  late final AtRefMenu _atMenu = AtRefMenu(cwd: () => Directory.current.path);
  late final KeymapDispatcher _keys = KeymapDispatcher(_controller.keymap);
  final TuiShellMode _shell = TuiShellMode();
  Timer? _spin;
  Timer? _exitTimer;
  int _tick = 0;
  bool _exiting = false;
  bool _confirmExit = false;
  ViewMode _view = ViewMode.chat;
  String _selectedText = '';
  int _selectionEpoch = 0;
  String _location = '';
  final List<TuiAttachment> _attachments = <TuiAttachment>[];

  @override
  void initState() {
    super.initState();
    _controller.onChanged = _refresh;
    _controller.onTabLeave = _saveTabScroll;
    _controller.onTabRestore = _restoreTabScroll;
    // /team 无参数时切视图；重复进同一视图会「切不回来」，故显式置位。
    _controller.onOpenTeamView = () => setState(() {
      _view = _view == ViewMode.team ? ViewMode.chat : ViewMode.team;
    });
    _input.addListener(_onInputChanged);
    _spin = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted) return;
      if (_controller.busy || _controller.recentTurnDuration != null) {
        setState(() => _tick++);
      }
    });
    unawaited(_controller.start());
    unawaited(_resolveLocation());
  }

  /// 解析状态栏位置信息（目录 + 分支）；失败时保持空串不显示右段。
  Future<void> _resolveLocation() async {
    final String location = await resolveWorkspaceLocation();
    if (mounted) {
      setState(() => _location = location);
    }
  }

  @override
  void dispose() {
    _spin?.cancel();
    _exitTimer?.cancel();
    _keys.dispose();
    _controller
      ..onChanged = null
      ..onTabLeave = null
      ..onTabRestore = null
      ..onOpenTeamView = null
      ..dispose();
    _input
      ..removeListener(_onInputChanged)
      ..dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 输入变化：同步 `/` 菜单与 `@` 文件补全并重绘。
  void _onInputChanged() {
    if (_enterShellMode()) {
      return;
    }
    if (_shell.active) {
      // shell 模式里 `/` 与 `@` 交给 shell 解释，不弹补全面板。
      _menu.close();
      _atMenu.close();
      _refresh();
      return;
    }
    _menu.syncInput(_input.text);
    final int cursor = _input.selection.baseOffset;
    _atMenu.syncInput(
      _input.text,
      cursor: cursor < 0 ? _input.text.length : cursor,
    );
    _refresh();
  }

  /// 输入以 `!` 开头 → 进入 shell 模式并剥掉 `!` 前缀（回显在输入框前缀上）；
  /// 未进入返回 false。
  bool _enterShellMode() {
    if (_controller.busy || !_shell.consumeBang(_input.text)) {
      return false;
    }
    _menu.close();
    _atMenu.close();
    _input.text = _input.text.substring(1);
    _input.selection = const TextSelection.collapsed(offset: 0);
    _refresh();
    return true;
  }

  void _refresh() {
    _takePrefill();
    if (mounted) {
      setState(() {});
    }
  }

  /// 取走控制器待回填的文本（`/undo` 回填被撤回的 prompt）并写入输入框。
  ///
  /// 只在首次取到值时改输入框；写入会触发输入监听（菜单/补全同步），
  /// 此时 prefill 已清空，不会递归。
  void _takePrefill() {
    final String? text = _controller.takePrefillInput();
    if (text == null || !mounted) return;
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
    _atMenu.close();
  }

  void _exit() {
    if (_exiting) {
      return;
    }
    _exiting = true;
    shutdownApp();
  }

  void _submit() {
    final String raw = _input.text;
    if (raw.trim().isEmpty && _attachments.isEmpty) {
      return;
    }
    if (_submitShell(raw)) {
      return;
    }
    _input.clear();
    // 占位标记映射回附件：文本里未出现的占位对应的附件（悬空）随清空丢弃。
    final AttachmentRefs refs = extractAttachmentRefs(raw);
    final List<TuiAttachment> attachments = <TuiAttachment>[
      for (final int index in refs.indices)
        if (index >= 1 && index <= _attachments.length) _attachments[index - 1],
    ];
    _attachments.clear();
    final String text = refs.text;
    if (text.trim().startsWith('/')) {
      unawaited(_controller.handleLine(text));
      setState(() {});
      return;
    }
    unawaited(_controller.handleLine(text, attachments: attachments));
    setState(() {});
  }

  /// shell 模式提交：交回 `!<命令>` 交给控制器执行，执行后自动退出模式；
  /// 不在 shell 模式返回 false。
  bool _submitShell(String raw) {
    if (!_shell.active) {
      return false;
    }
    final String command = _shell.submit(raw);
    _input.clear();
    if (command.isNotEmpty) {
      unawaited(_controller.handleLine(command));
    }
    _refresh();
    return true;
  }

  /// shell 模式按键：Esc 退出（不执行）、空输入时 Backspace 退出。
  bool _onShellKey(KeyboardEvent event) {
    if (!_shell.active) {
      return false;
    }
    final bool exited =
        event.logicalKey == LogicalKey.escape ||
        (_input.text.isEmpty && event.logicalKey == LogicalKey.backspace);
    if (!exited) {
      return false;
    }
    _shell.exit();
    _input.clear();
    _menu.close();
    _atMenu.close();
    _refresh();
    return true;
  }

  /// Ctrl+V 粘贴分派：剪贴板有文本时先按文件路径识别（终端拖放 / 复制路径），
  /// 识别不到交给输入框按普通文本插入；剪贴板无文本时尝试读系统剪贴板图片。
  ///
  /// bracketed paste 也会合成 Ctrl+V，其内容已写入剪贴板管理器，因此文本路径
  /// 天然覆盖拖放与 Cmd+V；纯图片时终端什么都不发，只能靠用户按 Ctrl+V 触发
  /// （此时剪贴板管理器为空，走图片通道）。
  bool _onPasteKey(KeyboardEvent event) {
    if (!event.matches(LogicalKey.keyV, ctrl: true)) {
      return false;
    }
    final String? clipboard = ClipboardManager.paste();
    if (clipboard != null && clipboard.isNotEmpty) {
      final List<TuiAttachment> found = extractPathAttachments(
        clipboard,
        Directory.current.path,
      );
      if (found.isNotEmpty) {
        _addAttachments(found);
        return true;
      }
      return false;
    }
    unawaited(_attachClipboardImage());
    return true;
  }

  /// 登记附件并往输入框插入占位标记（`[image #N (宽×高)]` / `[file #N (名)]`）；
  /// 超出上限时截断并提示。
  void _addAttachments(List<TuiAttachment> found) {
    final int room = kAttachmentMaxCount - _attachments.length;
    final List<TuiAttachment> accepted = found.take(room).toList();
    if (accepted.length < found.length) {
      _controller.transcript.add(
        TuiRole.system,
        '附件已达上限（$kAttachmentMaxCount 个），多余部分忽略。',
      );
    }
    setState(() {
      final StringBuffer buffer = StringBuffer(_input.text);
      for (final TuiAttachment attachment in accepted) {
        _attachments.add(attachment);
        buffer.write(
          '${attachmentPlaceholder(attachment, _attachments.length)} ',
        );
      }
      _input.text = buffer.toString();
    });
  }

  /// 从系统剪贴板读图片并登记为附件（macOS）。
  Future<void> _attachClipboardImage() async {
    final LlmImage? image = await readClipboardImage();
    if (!mounted) return;
    if (image == null) {
      _controller.transcript.add(TuiRole.system, '剪贴板中没有图片（复制截图后按 Ctrl+V 粘贴）。');
      _refresh();
      return;
    }
    try {
      final File file = await _saveTempImage(image);
      _addAttachments(<TuiAttachment>[
        TuiAttachment(path: file.path, mimeType: image.mimeType),
      ]);
    } catch (error) {
      _controller.transcript.add(TuiRole.system, '保存剪贴板图片失败：$error');
      _refresh();
    }
  }

  /// 剪贴板图片落盘临时文件（base64 随会话事件持久化，文件仅用于屏上标识）。
  Future<File> _saveTempImage(LlmImage image) {
    final String name =
        'conatus-paste-${DateTime.now().microsecondsSinceEpoch}.png';
    final File file = File('${Directory.systemTemp.path}/$name');
    return file.writeAsBytes(base64Decode(image.base64Data));
  }

  /// macOS Terminal.app 不区分 Ctrl+Tab 与 Tab（都发 0x09）；在普通输入态
  /// 把单独的 Tab / Shift+Tab 当作标签切换兜底。菜单/浮层打开时不处理，
  /// 避免抢占补全与表单切换。
  bool _onTabFallback(KeyboardEvent event) {
    if (event.logicalKey != LogicalKey.tab) return false;
    if (event.isControlPressed || event.isAltPressed || event.isMetaPressed) {
      return false;
    }
    if (_menu.open ||
        _atMenu.open ||
        _controller.picker.open ||
        _controller.agentPicker.open ||
        _controller.choice.open ||
        _controller.formPrompt.open ||
        _controller.modelPrompt.open ||
        _controller.providerPrompt.open ||
        _controller.renamePrompt.open ||
        _controller.themePrompt.open ||
        _controller.planPrompt.open ||
        _controller.permissionPrompt.open ||
        _controller.diffOpen) {
      return false;
    }
    unawaited(
      event.isShiftPressed
          ? _controller.activatePreviousTab()
          : _controller.activateNextTab(),
    );
    return true;
  }

  /// 全局键位：先问 dispatcher；leader 前缀或已被吞掉的第二段返回 true。
  bool _onGlobalKey(KeyboardEvent event) {
    final bool pendingBefore = _keys.leaderPending;
    final String? action = _keys.dispatch(event);
    if (action == null) {
      return pendingBefore || _keys.leaderPending;
    }
    _runKeyAction(action, event);
    return true;
  }

  /// 执行键位动作：全局动作映射到既有命令 / 视图切换。
  void _runKeyAction(String action, KeyboardEvent event) {
    switch (action) {
      case KeyActions.exit:
        _exitFromKey(event);
      case KeyActions.clear:
        _controller.transcript.clear();
        _refresh();
      case KeyActions.help:
        unawaited(_controller.handleLine('/help'));
        _refresh();
      case KeyActions.sessionNew:
        unawaited(_controller.handleLine('/new'));
      case KeyActions.sessionList:
        unawaited(_controller.handleLine('/sessions'));
      case KeyActions.modelList:
        unawaited(_controller.handleLine('/model'));
      case KeyActions.agentList:
        unawaited(_controller.handleLine('/agents'));
      case KeyActions.palette:
        _openPalette();
      case KeyActions.theme:
        unawaited(_controller.handleLine('/theme'));
      case KeyActions.tabNext:
        unawaited(_controller.activateNextTab());
      case KeyActions.tabPrevious:
        unawaited(_controller.activatePreviousTab());
      case KeyActions.tabClose:
        unawaited(_controller.closeActiveTab());
    }
  }

  /// 退出键：Ctrl+C 仍走既有清空 / 复制 / 打断 / 二次确认语义。
  void _exitFromKey(KeyboardEvent event) {
    if (event.matches(LogicalKey.keyC, ctrl: true) && _onCopyKey(event)) {
      return;
    }
    _exit();
  }

  /// `<leader>p`：把 `/` 写进输入框，触发命令菜单。
  void _openPalette() {
    _input.text = '/';
    _input.selection = const TextSelection.collapsed(offset: 1);
    _refresh();
  }

  /// 输入框按键拦截：`/` 菜单打开时用 ↑↓ 选择、Enter 运行、Tab 补全；
  /// Esc 一律返回 false 冒泡，由根组件 `_onKey` 统一处理（关闭面板/视图、打断轮次）。
  /// Ctrl+T（团队视图）/ Ctrl+Tab（会话标签，走可配置键位）、
  /// Ctrl+C/Alt+C 复制/打断/退出，Ctrl+V 粘贴（路径/图片），
  /// 均先于文本域消费。
  bool _onInputKey(KeyboardEvent event) {
    if (_onGlobalKey(event)) {
      return true;
    }
    if (_onShellKey(event)) {
      return true;
    }
    if (event.matches(LogicalKey.keyT, ctrl: true)) {
      _controller.togglePlanExpanded();
      return true;
    }
    if (event.matches(LogicalKey.keyO, ctrl: true)) {
      _controller.toggleToolExpanded();
      return true;
    }
    if (event.logicalKey == LogicalKey.backspace &&
        _input.text.isEmpty &&
        _attachments.isNotEmpty) {
      setState(_attachments.removeLast);
      return true;
    }
    if (_onPasteKey(event)) {
      return true;
    }
    if (_onCopyKey(event)) {
      return true;
    }
    if (_onChoiceKey(event)) {
      return true;
    }
    if (_onAtMenuKey(event)) {
      return true;
    }
    if (_onFormKey(event)) {
      return true;
    }
    if (_onModelKey(event)) {
      return true;
    }
    if (_onPermissionKey(event)) {
      return true;
    }
    if (_onThemeKey(event)) {
      return true;
    }
    if (_onProviderKey(event)) {
      return true;
    }
    if (_onPlanKey(event)) {
      return true;
    }
    if (!_menu.open) {
      return false;
    }
    if (event.logicalKey == LogicalKey.arrowUp) {
      _menu.move(-1);
      _refresh();
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowDown) {
      _menu.move(1);
      _refresh();
      return true;
    }
    if (event.logicalKey == LogicalKey.tab) {
      _completeSelected();
      return true;
    }
    if (event.logicalKey == LogicalKey.enter) {
      _runSelected();
      return true;
    }
    return false;
  }

  /// 表单浮层按键：Tab / ↑↓ 切字段、Enter 下一字段（末字段提交）、Esc 取消。
  bool _onFormKey(KeyboardEvent event) {
    final TuiFormPrompt form = _controller.formPrompt;
    if (!form.open) {
      return false;
    }
    if (event.logicalKey == LogicalKey.tab ||
        event.logicalKey == LogicalKey.arrowDown) {
      form.move(1);
    } else if (event.logicalKey == LogicalKey.arrowUp) {
      form.move(-1);
    } else if (event.logicalKey == LogicalKey.enter) {
      form.next();
    } else if (event.logicalKey == LogicalKey.escape) {
      form.cancel();
    } else {
      return false; // 其余按键交给字段输入框。
    }
    _refresh();
    return true;
  }

  /// 重命名浮层按键：Enter 提交、Esc 取消；其余交给输入框。
  bool _onRenameKey(KeyboardEvent event) {
    final TuiRenamePrompt prompt = _controller.renamePrompt;
    if (!prompt.open) {
      return false;
    }
    if (event.logicalKey == LogicalKey.enter) {
      unawaited(_controller.commitRename());
    } else if (event.logicalKey == LogicalKey.escape) {
      prompt.close();
    } else {
      return false; // 其余按键交给标题输入框。
    }
    _refresh();
    return true;
  }

  /// Plan 面板按键：Enter 进入/退出、Esc 关闭；未打开返回 false。
  bool _onPlanKey(KeyboardEvent event) {
    final TuiPlanPrompt prompt = _controller.planPrompt;
    if (!prompt.open) {
      return false;
    }
    if (event.logicalKey == LogicalKey.enter) {
      unawaited(_controller.confirmPlanPanel());
    } else if (event.logicalKey == LogicalKey.escape) {
      prompt.close();
    } else {
      return false;
    }
    _refresh();
    return true;
  }

  /// 模型浮层按键：Tab 切提供商、↑↓ 选择、Enter 确认、Esc 取消。
  bool _onModelKey(KeyboardEvent event) {
    final TuiModelPrompt prompt = _controller.modelPrompt;
    if (!prompt.open) {
      return false;
    }
    if (event.logicalKey == LogicalKey.tab) {
      prompt.toggleProvider();
    } else if (event.logicalKey == LogicalKey.arrowUp) {
      prompt.move(-1);
    } else if (event.logicalKey == LogicalKey.arrowDown) {
      prompt.move(1);
    } else if (event.logicalKey == LogicalKey.enter) {
      prompt.confirm();
    } else if (event.logicalKey == LogicalKey.escape) {
      prompt.cancel();
    } else {
      return false; // 其余按键交给搜索框（type to search）。
    }
    _refresh();
    return true;
  }

  /// 主题浮层按键：↑↓ 选择、Enter 应用、Esc 取消；未打开返回 false。
  bool _onThemeKey(KeyboardEvent event) {
    final ThemePrompt prompt = _controller.themePrompt;
    if (!prompt.open) {
      return false;
    }
    if (event.logicalKey == LogicalKey.arrowUp) {
      prompt.move(-1);
    } else if (event.logicalKey == LogicalKey.arrowDown) {
      prompt.move(1);
    } else if (event.logicalKey == LogicalKey.enter) {
      prompt.confirm();
    } else if (event.logicalKey == LogicalKey.escape) {
      prompt.cancel();
    } else {
      return false;
    }
    _refresh();
    return true;
  }

  /// 权限浮层按键：↑↓ 选择、Enter 确认、Esc 取消；未打开返回 false。
  bool _onPermissionKey(KeyboardEvent event) {
    final TuiPermissionPrompt prompt = _controller.permissionPrompt;
    if (!prompt.open) {
      return false;
    }
    if (event.logicalKey == LogicalKey.arrowUp) {
      prompt.move(-1);
    } else if (event.logicalKey == LogicalKey.arrowDown) {
      prompt.move(1);
    } else if (event.logicalKey == LogicalKey.enter) {
      prompt.confirm();
    } else if (event.logicalKey == LogicalKey.escape) {
      prompt.cancel();
    } else {
      return false;
    }
    _refresh();
    return true;
  }

  /// provider 浮层按键：↑↓ 选择、Enter 确认 / 切换、Esc 关闭。
  bool _onProviderKey(KeyboardEvent event) {
    final TuiProviderPrompt prompt = _controller.providerPrompt;
    if (!prompt.open) {
      return false;
    }
    if (event.logicalKey == LogicalKey.arrowUp) {
      prompt.move(-1);
    } else if (event.logicalKey == LogicalKey.arrowDown) {
      prompt.move(1);
    } else if (event.logicalKey == LogicalKey.enter) {
      if (prompt.awaiting) {
        prompt.confirm();
      } else {
        unawaited(_controller.confirmProviderItem());
      }
    } else if (event.logicalKey == LogicalKey.escape) {
      prompt.cancel();
    } else {
      return false;
    }
    _refresh();
    return true;
  }

  /// `@` 文件补全按键：↑↓ 移动、Tab/Enter 补全、Esc 关闭；未打开返回 false。
  bool _onAtMenuKey(KeyboardEvent event) {
    if (!_atMenu.open) {
      return false;
    }
    if (event.logicalKey == LogicalKey.arrowUp) {
      _atMenu.move(-1);
    } else if (event.logicalKey == LogicalKey.arrowDown) {
      _atMenu.move(1);
    } else if (event.logicalKey == LogicalKey.tab ||
        event.logicalKey == LogicalKey.enter) {
      _completeAtRef();
      return true;
    } else if (event.logicalKey == LogicalKey.escape) {
      _atMenu.close();
    } else {
      return false; // 其余按键交给输入框（继续打字）。
    }
    _refresh();
    return true;
  }

  /// 把选中候选补进输入框：目录停在路径末尾（继续列举），文件追加空格收尾。
  void _completeAtRef() {
    final (String, int)? result = _atMenu.complete(
      _input.text,
      cursor: _input.selection.baseOffset,
    );
    if (result == null) {
      return;
    }
    final (String text, int cursor) = result;
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: cursor);
    _atMenu.syncInput(text, cursor: cursor);
    _refresh();
  }

  /// Tab：把选中命令补全到输入框，不立即执行（带参命令留一个空格）。
  void _completeSelected() {
    final TuiCommand? command = _menu.selected;
    if (command == null) {
      return;
    }
    _input.text = command.takesArgs ? '${command.token} ' : command.token;
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    _menu.close(); // 覆盖 setText 触发的自动重开
    _refresh();
  }

  /// Enter：无参命令直接运行；带参命令补全后等用户补参数。
  void _runSelected() {
    final TuiCommand? command = _menu.selected;
    if (command == null) {
      return;
    }
    if (command.takesArgs) {
      _completeSelected();
      return;
    }
    _menu.close();
    _input.clear();
    unawaited(_controller.handleLine(command.token));
    setState(() {});
  }

  /// 选项浮层按键：↑↓ 移动、Enter 确认、Esc 取消；项目面板额外支持 r 重命名。
  bool _onChoiceKey(KeyboardEvent event) {
    final TuiChoicePrompt prompt = _controller.choice;
    if (!prompt.open) {
      return false;
    }
    if (event.logicalKey == LogicalKey.arrowUp) {
      prompt.move(-1);
    } else if (event.logicalKey == LogicalKey.arrowDown) {
      prompt.move(1);
    } else if (event.logicalKey == LogicalKey.enter) {
      prompt.confirm();
    } else if (event.logicalKey == LogicalKey.escape) {
      prompt.cancel();
    } else if (event.logicalKey == LogicalKey.keyR &&
        prompt.request?.showRename == true) {
      _controller.renameSelectedProject();
    }
    return true; // 浮层打开时吞掉按键，避免误输入。
  }

  /// Ctrl+C / Alt+C / Cmd+C：平台差异化按键语义。
  ///
  /// 输入框有内容时 Ctrl+C 恒为清空输入（shell 习惯）。
  /// macOS：Ctrl+C 忙时打断在飞轮次；空闲时有选区先复制、无选区连按两次
  /// 退出；复制还可走 Alt+C（Option+C，终端必转发）或 Cmd+C（取决于终端
  /// 是否把 Cmd 键转发给应用）。其他平台：Ctrl+C 有选中文本时复制，
  /// 否则连按两次退出。Alt+C / Cmd+C 无选区也吞掉，避免被当作字符输入。
  bool _onCopyKey(KeyboardEvent event) {
    if (event.logicalKey != LogicalKey.keyC) {
      return false;
    }
    if (event.isControlPressed) {
      if (_input.text.isNotEmpty) {
        _input.clear();
        return true;
      }
      if (Platform.isMacOS && _controller.busy) {
        _controller.interrupt();
        return true;
      }
      if (!_controller.choice.open &&
          !_controller.picker.open &&
          _copySelection()) {
        return true;
      }
      _confirmExitChord();
      return true;
    }
    if (Platform.isMacOS && (event.isAltPressed || event.isMetaPressed)) {
      if (!_controller.choice.open && !_controller.picker.open) {
        _copySelection();
      }
      return true;
    }
    return false;
  }

  bool _onKey(KeyboardEvent event) {
    if (_onGlobalKey(event)) {
      return true;
    }
    // 主题浮层是模态：输入栏让出焦点，按键（含 Esc）由根组件统一处理。
    if (_onThemeKey(event)) {
      return true;
    }
    // diff 视图打开时 Esc 一律关闭它（视图自己也会处理，这里兜底焦点异常）。
    if (_controller.diffOpen && event.logicalKey == LogicalKey.escape) {
      _controller.closeDiff();
      return true;
    }
    // Ctrl+T 在团队视图下切视图（TeamView 的提示语一直这么写，此前与 TODO
    // 展开撞了——同一按键两种行为，提示语还是在骗人）。对话视图下才是展开
    // TODO 列表（兜底：输入框聚焦时由 _onInputKey 先行处理）。
    if (event.matches(LogicalKey.keyT, ctrl: true)) {
      if (_view == ViewMode.team) {
        _toggleView();
      } else {
        _controller.togglePlanExpanded();
      }
      return true;
    }
    // Ctrl+O 展开 / 收起最近一条工具结果。
    if (event.matches(LogicalKey.keyO, ctrl: true)) {
      _controller.toggleToolExpanded();
      return true;
    }
    // Ctrl+C / Alt+C：平台差异化语义，见 _onCopyKey。
    if (_onCopyKey(event)) {
      return true;
    }
    if (_onRenameKey(event)) {
      return true;
    }
    if (_onChoiceKey(event)) {
      return true;
    }
    if (_onFormKey(event)) {
      return true;
    }
    if (_onModelKey(event)) {
      return true;
    }
    if (_onProviderKey(event)) {
      return true;
    }
    if (_onPlanKey(event)) {
      return true;
    }
    if (_controller.agentPicker.open) {
      if (event.logicalKey == LogicalKey.arrowUp) {
        _controller.moveAgentPicker(-1);
      } else if (event.logicalKey == LogicalKey.arrowDown) {
        _controller.moveAgentPicker(1);
      } else if (event.logicalKey == LogicalKey.enter) {
        unawaited(_controller.pickAgent());
      } else if (event.logicalKey == LogicalKey.escape) {
        _controller.closeAgentPicker();
      }
      return true; // 面板打开时吞掉按键，避免误输入。
    }
    if (_controller.picker.open) {
      if (event.logicalKey == LogicalKey.arrowUp) {
        _controller.movePicker(-1);
      } else if (event.logicalKey == LogicalKey.arrowDown) {
        _controller.movePicker(1);
      } else if (event.logicalKey == LogicalKey.keyR) {
        unawaited(_controller.openRenameForSelected());
      } else if (event.logicalKey == LogicalKey.keyD) {
        unawaited(_controller.deleteSelectedSession());
      } else if (event.logicalKey == LogicalKey.enter) {
        unawaited(_controller.pickSelected());
      } else if (event.logicalKey == LogicalKey.escape) {
        _controller.closePicker();
      }
      return true; // 面板打开时吞掉按键，避免误输入。
    }
    // Esc 兜底（choice/picker 的 Esc 已在上方处理）：关闭菜单、关闭帮助弹出、
    // 团队视图返回，无面板时打断在飞轮次（busy 时输入框 readOnly 不经
    // _onInputKey，靠这里兜底）。
    if (_onTabFallback(event)) {
      return true;
    }
    if (event.logicalKey == LogicalKey.escape) {
      if (_menu.open) {
        _menu.close();
        _refresh();
        return true;
      }
      if (_atMenu.open) {
        _atMenu.close();
        _refresh();
        return true;
      }
      if (_controller.formPrompt.open) {
        _controller.formPrompt.cancel();
        return true;
      }
      if (_controller.providerPrompt.open) {
        _controller.providerPrompt.close();
        return true;
      }
      if (_controller.modelPrompt.open) {
        _controller.modelPrompt.close();
        return true;
      }
      if (_controller.planPrompt.open) {
        _controller.planPrompt.close();
        return true;
      }
      if (_controller.transcript.closeHelp()) {
        _refresh();
        return true;
      }
      if (_view == ViewMode.team) {
        _toggleView();
        return true;
      }
      _controller.interrupt();
      return true;
    }
    return false;
  }

  /// 复制当前选中文本：消息区选区优先，其次输入框选区；无选区返回 false。
  bool _copySelection() {
    final String text = _selectedText.isNotEmpty
        ? _selectedText
        : _selectedInputText();
    if (text.isEmpty) {
      return false;
    }
    unawaited(copySelectionToSystemClipboard(text));
    _clearSelection();
    return true;
  }

  /// 输入框内选中文本；无选区返回空串。
  String _selectedInputText() {
    final TextSelection selection = _input.selection;
    if (selection.isCollapsed) {
      return '';
    }
    return _input.text.substring(selection.start, selection.end);
  }

  /// 复制后清除消息区与输入框选区：重建 SelectionArea 以撤销消息区高亮。
  void _clearSelection() {
    _selectedText = '';
    if (!_input.selection.isCollapsed) {
      _input.selection = TextSelection.collapsed(
        offset: _input.selection.extentOffset,
      );
    }
    setState(() => _selectionEpoch++);
  }

  /// Ctrl+C：首次挂起退出确认并计时复位，窗口内再按一次才真正退出。
  void _confirmExitChord() {
    if (_confirmExit) {
      _exit();
      return;
    }
    _exitTimer?.cancel();
    setState(() => _confirmExit = true);
    _exitTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _confirmExit = false);
      }
    });
  }

  /// 切换对话 / 团队视图。
  void _toggleView() {
    setState(() {
      _view = _view == ViewMode.chat ? ViewMode.team : ViewMode.chat;
    });
  }

  /// 离开标签前记录聊天滚动位置（切换成功后由 [_restoreTabScroll] 恢复）。
  void _saveTabScroll() {
    if (_controller.ready) {
      _controller.tabs.saveScroll(_scroll.offset);
    }
  }

  /// 切回标签后恢复滚动位置：等目标会话内容完成布局再跳。
  void _restoreTabScroll(double offset) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scroll.jumpTo(offset);
      }
    });
  }

  @override
  Component build(BuildContext context) {
    return Focusable(
      // 带输入框的浮层（表单 / 模型搜索 / 重命名）打开时让出焦点，由浮层内的
      // TextField 接收字符与按键（其 onKeyEvent 即浮层按键处理）。
      focused:
          !_controller.modelPrompt.open &&
          !_controller.formPrompt.open &&
          !_controller.renamePrompt.open,
      onKeyEvent: _onKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Component>[
          TabBar(
            tabs: _controller.tabs.tabs,
            active: _controller.tabs.active,
            nextHint: _controller.keymap
                .displayLabelsFor(KeyActions.tabNext)
                .join(', '),
            closeHint: _controller.keymap
                .displayLabelsFor(KeyActions.tabClose)
                .join(', '),
          ),
          Expanded(
            child: _view == ViewMode.chat
                ? (_controller.diffOpen ? _diffView() : _body())
                : TeamView(snapshot: _controller.teamSnapshot),
          ),
          // 交互浮层一律贴在输入栏上方（小面板），消息区保持可见。
          if (_controller.renamePrompt.open)
            TuiRenameView(
              prompt: _controller.renamePrompt,
              onKeyEvent: _onRenameKey,
            ),
          if (_controller.choice.open)
            TuiChoiceView(
              request: _controller.choice.request!,
              selected: _controller.choice.index,
            ),
          if (_controller.picker.open)
            SessionPickerView(
              sessions: _controller.picker.list,
              currentId: _controller.sessionId,
              selected: _controller.picker.index,
            ),
          if (_controller.agentPicker.open)
            AgentPickerView(picker: _controller.agentPicker),
          if (_controller.formPrompt.open)
            TuiFormView(
              request: _controller.formPrompt.request!,
              index: _controller.formPrompt.index,
              onKeyEvent: _onFormKey,
            ),
          if (_controller.providerPrompt.open)
            TuiProviderView(
              items: _controller.providerPrompt.items,
              selected: _controller.providerPrompt.index,
              title: _controller.providerPrompt.title,
              hint: _controller.providerPrompt.hint,
            ),
          if (_controller.modelPrompt.open)
            TuiModelView(
              prompt: _controller.modelPrompt,
              onKeyEvent: _onModelKey,
            ),
          if (_controller.permissionPrompt.open)
            TuiPermissionView(prompt: _controller.permissionPrompt),
          if (_controller.themePrompt.open)
            ThemeView(
              names: _controller.themePrompt.names,
              selected: _controller.themePrompt.index,
              current: _controller.themePrompt.current,
            ),
          if (_controller.planPrompt.open)
            TuiPlanView(prompt: _controller.planPrompt),
          if (_menu.open)
            TuiCommandMenuView(
              matches: _menu.matches,
              selected: _menu.index,
              windowStart: _menu.windowStart,
            ),
          if (_atMenu.open)
            AtRefMenuView(matches: _atMenu.matches, selected: _atMenu.index),
          TeamStatusBar(snapshot: _controller.teamSnapshot),
          if (!_controller.diffOpen)
            TuiInputBar(
              controller: _input,
              shellMode: _shell.active,
              focused:
                  !_controller.picker.open &&
                  !_controller.agentPicker.open &&
                  !_controller.choice.open &&
                  !_controller.providerPrompt.open &&
                  !_controller.formPrompt.open &&
                  !_controller.modelPrompt.open &&
                  !_controller.renamePrompt.open &&
                  !_controller.themePrompt.open,
              busy: _controller.busy,
              queuedCount: _controller.queuedCount,
              onSubmitted: (_) => _submit(),
              onKeyEvent: _onInputKey,
            ),
          TuiStatusBar(
            shellMode: _shell.active,
            pickerOpen: _controller.picker.open || _controller.agentPicker.open,
            busy: _controller.busy,
            tick: _tick,
            turnElapsed: _controller.turnElapsed,
            recentTurnDuration: _controller.recentTurnDuration,
            recentTurnStatus: _controller.recentTurnStatus,
            modelLabel: _controller.modelLabel,
            projectName: _controller.projectName ?? '',
            location: _location,
            contextText: formatContextUsage(
              _controller.contextTokens,
              _controller.modelContextLength,
              estimated: _controller.contextTokensEstimated,
            ),
            menuOpen: _menu.open,
            choiceOpen: _controller.choice.open,
            exitPending: _confirmExit,
            permissionLabel: _controller.permissionLabel,
            hasSelection: _selectedText.isNotEmpty,
          ),
        ],
      ),
    );
  }

  /// `/diff` 全屏视图：状态由控制器持有，按键与当前文件由视图自己管理。
  Component _diffView() {
    return TuiDiffView(
      diffs: _controller.diffFiles,
      scope: _controller.diffScope,
      notice: _controller.diffNotice,
      onClose: _controller.closeDiff,
      onSwitchScope: _controller.setDiffScope,
    );
  }

  /// 浮层优先渲染：选项 / 会话面板 / 表单 / provider；无浮层返回 `null`。
  Component _body() {
    if (!_controller.ready) {
      return Center(
        child: Text(
          '正在加载会话…',
          style: TextStyle(color: NavaTheme.palette.muted),
        ),
      );
    }
    final List<TuiMessage> messages = _controller.transcript.messages;
    final bool loading = _controller.busy;
    if (messages.isEmpty && !loading) {
      return Center(
        child: Text(
          '输入文字开始对话；/help 查看命令。',
          style: TextStyle(color: NavaTheme.palette.muted),
        ),
      );
    }
    final child = Scrollbar(
      controller: _scroll,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(1),
        itemCount: messages.length + (loading ? 1 : 0),
        itemBuilder: (BuildContext context, int index) {
          if (index < messages.length) {
            return MessageView(message: messages[index]);
          }
          return LoadingView(tick: _tick);
        },
      ),
    );
    // key 变化时重建，用于复制后撤销鼠标选区（nocterm 无公开清除 API）。
    return SelectionArea(
      key: ValueKey<int>(_selectionEpoch),
      onSelectionChanged: (String text) {
        _selectedText = text;
        _refresh(); // 让状态栏「可复制」提示随选区出现/消失。
      },
      // 选区完成即复制（copy-on-select）：与 Kimi Code 一致，选中后
      // 无需按复制键即可在系统任意处粘贴；macOS 经 pbcopy 直写剪贴板。
      onSelectionCompleted: (String text) =>
          unawaited(copySelectionToSystemClipboard(text)),
      child: child,
    );
  }
}
