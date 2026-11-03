/// 启动耗时采样：`main` 入口 → 配置装载 → runtime 装配 → TUI 首帧。
library;

/// 启动各阶段的时间戳（相对 `StartupTiming` 构造时刻）。
///
/// 口径：从 `main` 第一行起算，**不含** Dart VM / AOT 映像加载；后者用
/// `time nava --version` 量。`/doctor` 的「启动耗时」一格读这里。
class StartupTiming {
  StartupTiming({Duration Function()? now}) : _now = now;

  /// 测试注入的假时钟；为 null 时用内部单调 [Stopwatch]。
  final Duration Function()? _now;
  final Stopwatch _clock = Stopwatch()..start();

  Duration? _configLoaded;
  Duration? _runtimeReady;
  Duration? _firstFrame;

  Duration get _elapsed => _now?.call() ?? _clock.elapsed;

  void markConfigLoaded() => _configLoaded = _elapsed;

  void markRuntimeReady() => _runtimeReady = _elapsed;

  void markFirstFrame() => _firstFrame = _elapsed;

  /// `/doctor` 文案，如 `总 412ms（配置 38 · 装配 320 · 首帧 54）`。
  ///
  /// 没打到的里程碑（headless 没有首帧）逐项标注「未记录」；一个点都没有
  /// （库用法不传采样器）时如实说「未采集」。
  String describe() {
    if (_configLoaded == null) return '未采集';
    final List<String> parts = <String>[];
    final List<String> missing = <String>[];
    Duration total = Duration.zero;
    for (final (String label, Duration? at) in _milestones) {
      if (at == null) {
        missing.add(label);
        continue;
      }
      parts.add('$label ${(at - total).inMilliseconds}');
      total = at;
    }
    final String detail = parts.join(' · ');
    if (missing.isEmpty) return '总 ${total.inMilliseconds}ms（$detail）';
    return '总 ${total.inMilliseconds}ms'
        '（$detail；${missing.join('、')}未记录）';
  }

  List<(String, Duration?)> get _milestones => <(String, Duration?)>[
    ('配置', _configLoaded),
    ('装配', _runtimeReady),
    ('首帧', _firstFrame),
  ];
}
