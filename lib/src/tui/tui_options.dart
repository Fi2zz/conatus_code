/// conatus_code 入口的命令行选项：解析 `--session` / `--config` / `--help`。
///
/// 从入口 `main` 里提出来，调用方（自己的 `main` 或别的入口）因此能复用同一套
/// 解析与用法文案，不必再抄一遍。
library;

/// 会话 id 规则：字母 / 数字 / 下划线 / 中文 / 短横，长度 1—64。
///
/// 这是 TUI 内部（`/session` 切换、会话面板）的宽松校验；CLI 恢复判定用的是
/// [isCanonicalSessionId]。
bool isValidSessionId(String id) =>
    RegExp(r'^[A-Za-z0-9_\-\u4e00-\u9fff]{1,64}$').hasMatch(id);

/// 规范会话 id：`session_` + UUID（如 `session_c8898262-4a76-4bd4-93dc-f757fd4ef666`）。
///
/// 只有命中该格式的 id 才可被 `nava --session <id>` 打开/恢复；其余一律视为
/// 新建会话。
bool isCanonicalSessionId(String id) => RegExp(
    r'^session_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false).hasMatch(id);

/// 命令行选项。
class TuiOptions {
  /// 构造选项。
  const TuiOptions({
    this.session,
    this.configPath,
    this.helpRequested = false,
    this.print,
    this.outputFormat = 'text',
    this.versionRequested = false,
    this.continueRequested = false,
  });

  /// 要打开/恢复的会话 id；`null` 表示新建会话（缺省）。
  final String? session;

  /// `--config` 指定的配置文件路径；`null` 表示用默认位置。
  final String? configPath;

  /// 命令行里是否出现了 `--help` / `-h`。
  ///
  /// 解析本身不打印也不退出，由调用方决定怎么处理。
  final bool helpRequested;

  /// `-p` / `--print` 的任务文本；非空时进入 headless 单轮执行（不启动 TUI）。
  final String? print;

  /// headless 输出格式：`text`（缺省）或 `json`；非法值回落 `text`。
  final String outputFormat;

  /// 命令行里是否出现了 `--version`；打印版本后退出。
  final bool versionRequested;

  /// 是否出现了 `--continue`：恢复最近一次会话（无 `--session` 时生效）。
  final bool continueRequested;

  /// 用法文案。
  static const String usage =
      '用法：nava '
      '[--session <id>] [--config <路径>]\n'
      '       nava -p <任务文本> [--output-format text|json] [--session <id>]\n'
      '  --session <id>   打开/恢复指定会话（缺省新建会话，格式 session_<uuid>）\n'
      '  --config <路径>  配置文件路径（默认 ~/.nava/config.toml）\n'
      '  -p, --print <任务>  headless 单轮执行：跑完即退出，不启动 TUI\n'
      '  --output-format   headless 输出格式：text / json（缺省 text）\n'
      '  --continue        恢复最近一次会话（--session 优先于它）\n'
      '  --version         打印版本号后退出\n';

  /// 解析命令行参数。
  ///
  /// `--session <id>` 出现且 id 为规范格式（`session_<uuid>`）时用它；`--session`
  /// 无值、后一个参数以 `-` 开头、或取值不是规范格式时，都视为未指定会话
  /// （返回 `session: null`，由调用方新建会话），不抛错。
  // REASON: 命令行选项解析天然是 if-else 链（一个选项一个分支），表驱动反而更难读。
  static TuiOptions parse(List<String> args) {
    String? session;
    String? configPath;
    bool helpRequested = false;
    String? print;
    String outputFormat = 'text';
    bool versionRequested = false;
    bool continueRequested = false;
    for (int index = 0; index < args.length; index++) {
      final String arg = args[index];
      if (arg == '--help' || arg == '-h') {
        helpRequested = true;
      } else if (arg == '--version') {
        versionRequested = true;
      } else if (arg == '--continue') {
        continueRequested = true;
      } else if (arg == '--session') {
        final bool hasValue =
            index + 1 < args.length && !args[index + 1].startsWith('-');
        if (hasValue) {
          final String candidate = args[++index];
          if (isCanonicalSessionId(candidate)) {
            session = candidate;
          }
        }
      } else if (arg == '--config' && index + 1 < args.length) {
        configPath = args[++index];
      } else if (arg == '--print' || arg == '-p') {
        final bool hasValue =
            index + 1 < args.length && !args[index + 1].startsWith('-');
        if (hasValue) {
          print = args[++index];
        }
      } else if (arg == '--output-format' && index + 1 < args.length) {
        final String candidate = args[++index];
        if (candidate == 'json') {
          outputFormat = 'json';
        }
      }
    }
    return TuiOptions(
      session: session,
      configPath: configPath,
      helpRequested: helpRequested,
      print: print,
      outputFormat: outputFormat,
      versionRequested: versionRequested,
      continueRequested: continueRequested,
    );
  }
}
