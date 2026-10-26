/// Agent / 命令定义目录的变更监听：把密集事件合并成一次重载信号。
library;

import 'dart:async';
import 'dart:io';

import 'package:conatus_core/conatus_core.dart';

/// 监听一组定义目录；只监听启动时已存在的目录。
class DefinitionWatcher {
  /// 构造监听器。
  DefinitionWatcher({
    required this.roots,
    required this.onInvalidate,
    this.debounce = const Duration(milliseconds: 250),
  });

  /// 要监听的目录。
  final List<String> roots;

  /// 变更合并后的失效出口。
  final void Function() onInvalidate;

  /// 事件到失效之间的合并窗口。
  final Duration debounce;

  final List<StreamSubscription<FileSystemEvent>> _subscriptions =
      <StreamSubscription<FileSystemEvent>>[];
  Timer? _timer;
  bool _stopped = false;

  /// 对每个已存在的根起监听；返回停止函数（幂等）。
  Disposer start() {
    for (final String root in roots.toSet()) {
      final Directory directory = Directory(root);
      if (!directory.existsSync()) continue;
      _subscriptions.add(
        directory.watch(recursive: true).listen(
              _onEvent,
              onError: (Object _, StackTrace __) {},
            ),
      );
    }
    return stop;
  }

  /// 停止监听；已排队的失效信号一并取消。
  void stop() {
    if (_stopped) return;
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    for (final StreamSubscription<FileSystemEvent> subscription
        in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  void _onEvent(FileSystemEvent event) {
    if (_stopped) return;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _timer = null;
      if (!_stopped) onInvalidate();
    });
  }
}
