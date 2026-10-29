/// 会话 UI 状态：滚动位置与输入历史的 sidecar 持久化。
library;

import 'dart:convert';
import 'dart:io';

import '../config/config_atomic_write.dart';

/// 一个会话的可恢复 UI 状态。
class SessionUiState {
  const SessionUiState({this.scrollOffset, this.history = const <String>[]});

  /// 聊天区滚动偏移；`null` 表示没有记录（首次打开回到末尾）。
  final double? scrollOffset;

  /// 用户提交过的输入，最旧在前。
  final List<String> history;

  /// 空状态。
  static const SessionUiState empty = SessionUiState();

  /// 带新滚动位置的副本。
  SessionUiState withScroll(double offset) =>
      SessionUiState(scrollOffset: offset, history: history);

  /// 带追加历史的副本（连续重复折叠；最多 [kSessionUiHistoryLimit] 条）。
  SessionUiState withInput(String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return this;
    final List<String> next = List<String>.of(history);
    if (next.isNotEmpty && next.last == text) return this;
    next.add(text);
    if (next.length > kSessionUiHistoryLimit) {
      next.removeRange(0, next.length - kSessionUiHistoryLimit);
    }
    return SessionUiState(scrollOffset: scrollOffset, history: next);
  }
}

/// 输入历史上限。
const int kSessionUiHistoryLimit = 100;

/// 会话 UI 状态存储；损坏或缺失时退化为空状态。
class SessionUiStateStore {
  SessionUiStateStore({required this.dir});

  /// sidecar 目录。
  final String dir;

  /// 读取 [sessionId] 的状态；不存在、损坏或版本不认识时返回空状态。
  Future<SessionUiState> load(String sessionId) async {
    final File file = _file(sessionId);
    if (!file.existsSync()) return SessionUiState.empty;
    try {
      final Object? json = jsonDecode(await file.readAsString());
      if (json is! Map) return SessionUiState.empty;
      if (json['version'] != 1) return SessionUiState.empty;
      final Object? rawOffset = json['scrollOffset'];
      final double? offset = rawOffset is num && rawOffset.isFinite
          ? rawOffset.toDouble()
          : null;
      final List<String> history = <String>[];
      final Object? rawHistory = json['history'];
      if (rawHistory is List) {
        for (final Object? item in rawHistory) {
          if (item is String && item.trim().isNotEmpty) history.add(item);
        }
      }
      return SessionUiState(
        scrollOffset: offset,
        history: List<String>.unmodifiable(
          history.length > kSessionUiHistoryLimit
              ? history.sublist(history.length - kSessionUiHistoryLimit)
              : history,
        ),
      );
    } on FormatException {
      return SessionUiState.empty;
    } on FileSystemException {
      return SessionUiState.empty;
    }
  }

  /// 原子写入状态；父目录自动创建，权限 0600。
  Future<void> save(String sessionId, SessionUiState state) async {
    final Map<String, Object?> json = <String, Object?>{
      'version': 1,
      if (state.scrollOffset != null) 'scrollOffset': state.scrollOffset,
      'history': state.history,
    };
    writeFileAtomic(_file(sessionId).path, '${jsonEncode(json)}\n');
  }

  File _file(String sessionId) {
    final String safe = sessionId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return File('$dir${Platform.pathSeparator}$safe.json');
  }
}
