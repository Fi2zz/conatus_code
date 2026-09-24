/// 编译期注入的 nava 版本号。
///
/// 源码运行（`dart run`）时为 `dev`；打包脚本 `tool/build_binary.sh` 从
/// `pubspec.yaml` 抽版本并以 `-DNAVA_VERSION=<版本>` 编译注入。
library;

/// nava 版本号。
const String navaVersion = String.fromEnvironment(
  'NAVA_VERSION',
  defaultValue: 'dev',
);
