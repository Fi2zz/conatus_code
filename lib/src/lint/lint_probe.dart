/// 「编辑后校验」探针：按项目类型决定跑什么命令、输出能不能结构化解析。
///
/// 分层的理由：Dart 项目可以**按改动文件**限定范围并拿到定长机器格式，而 Go /
/// Rust 的校验单位是 package / crate（`go vet ./...`、`cargo check` 没法只查一个
/// 文件），ESLint 尚无实测。因此只有探针自己声明 [LintProbe.scopesToFiles]，调用方
/// 才知道该不该把路径塞进命令。
library;

import 'dart:io';

/// 探针输出的可解析形态。
enum LintOutputFormat {
  /// `dart analyze --format=machine`：管道分隔定长字段，可结构化。
  dartMachine,

  /// 人类可读文本，原样截断回传给模型。
  rawText,
}

/// 一条探针定义（命令 + 输出形态）。
class LintProbe {
  const LintProbe({required this.command, required this.format});

  /// 命令模板。含 `{file}` 占位符时按改动文件限定范围，否则跑全项目。
  final String command;

  /// 输出形态，决定怎么解析、怎么渲染。
  final LintOutputFormat format;

  /// 命令是否支持按文件限定。
  bool get scopesToFiles => command.contains('{file}');
}

/// 标记文件 + 对应探针；按声明顺序取第一个命中的。
class _Marker {
  const _Marker(this.file, this.command, this.format);

  final String file;
  final String command;
  final LintOutputFormat format;
}

// REASON: 这是一张静态映射表（项目标记 → 校验命令），刻意写成数据而不是
// if 链：新增语言只加一行，且探测顺序（同时命中多个标记时谁优先）一眼可见。
const List<_Marker> _kMarkers = <_Marker>[
  // 实测：全仓 `dart analyze` 2.3s；限定到改动文件 0.3~0.5s，且输出可解析成
  // 结构化 code（`RETURN_OF_INVALID_TYPE` 等），比纯文本更适合模型定位与修复。
  _Marker(
    'pubspec.yaml',
    'dart analyze --format=machine {file}',
    LintOutputFormat.dartMachine,
  ),
  _Marker('go.mod', 'go vet ./...', LintOutputFormat.rawText),
  _Marker('Cargo.toml', 'cargo check', LintOutputFormat.rawText),
  _Marker('package.json', 'eslint .', LintOutputFormat.rawText),
];

/// 按项目标记文件探测探针；认不出来返回 `null`（不跑校验）。
LintProbe? detectLintProbe(String workdir) {
  for (final _Marker marker in _kMarkers) {
    final String path =
        '$workdir${Platform.pathSeparator}${marker.file}';
    if (File(path).existsSync()) {
      return LintProbe(command: marker.command, format: marker.format);
    }
  }
  return null;
}
