/// conatus_code 入口的命令行选项：解析 `--session` / `--first` / `--config` / `--help`。
///
/// 从入口 `main` 里提出来，调用方（自己的 `main` 或别的入口）因此能复用同一套
/// 解析与用法文案，不必再抄一遍。
library;

/// 会话 id 规则：字母 / 数字 / 下划线 / 中文 / 短横，长度 1—64。
bool isValidSessionId(String id) =>
    RegExp(r'^[A-Za-z0-9_\-\u4e00-\u9fff]{1,64}$').hasMatch(id);

/// 缺省启动会话 id。
const String kTuiDefaultSession = 'tui';

/// 命令行选项。
class TuiOptions {
  /// 构造选项。
  const TuiOptions({
    this.session = kTuiDefaultSession,
    this.first,
    this.configPath,
    this.helpRequested = false,
  });

  /// 启动会话 id。
  final String session;

  /// 挂载后自动发送的首轮输入；`null` 表示不发。
  final String? first;

  /// `--config` 指定的配置文件路径；`null` 表示用默认位置。
  final String? configPath;

  /// 命令行里是否出现了 `--help` / `-h`。
  ///
  /// 解析本身不打印也不退出，由调用方决定怎么处理。
  final bool helpRequested;

  /// 用法文案。
  static const String usage = '用法：dart run conatus_code '
      '[--session <id>] [--first <文本>] [--config <路径>]\n'
      '  --session <id>   启动会话 id（默认 tui）\n'
      '  --first <文本>   挂载后自动发一轮\n'
      '  --config <路径>  配置文件路径（默认 ~/.conatus-code/config.toml）\n';

  /// 解析命令行参数。
  ///
  /// [sessionId] 是 `--session` 未出现时的启动会话；`--session` 出现且取值合法
  /// 时以它为准。最终选中的会话 id 不是合法会话 id 时抛 [ArgumentError]。
  // REASON: 命令行选项解析天然是 if-else 链（一个选项一个分支），表驱动反而更难读。
  static TuiOptions parse(
    List<String> args, {
    String sessionId = kTuiDefaultSession,
  }) {
    String session = sessionId;
    String? first;
    String? configPath;
    bool helpRequested = false;
    for (int index = 0; index < args.length; index++) {
      final String arg = args[index];
      if (arg == '--help' || arg == '-h') {
        helpRequested = true;
      } else if (arg == '--session' && index + 1 < args.length) {
        session = args[++index];
      } else if (arg == '--first' && index + 1 < args.length) {
        first = args[++index];
      } else if (arg == '--config' && index + 1 < args.length) {
        configPath = args[++index];
      }
    }
    if (!isValidSessionId(session)) {
      throw ArgumentError.value(session, 'sessionId', '必须是合法会话 id');
    }
    return TuiOptions(
      session: session,
      first: first,
      configPath: configPath,
      helpRequested: helpRequested,
    );
  }
}
