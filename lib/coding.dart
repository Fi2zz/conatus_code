/// conatus_code 的 coding 场景入口：代码读写 / 搜索定位复用同包的 fs_tools
/// 入口（`lib/fs_tools.dart`），本入口提供代码执行层（[CodeRuntime] 接缝 +
/// 子进程后端）与绑定桥接。
///
/// **实验性**：API 可能在没有 major 版本变更的情况下调整，勿在生产环境依赖。
library;

export 'src/coding/binding/tool_binding.dart' show toolsAsBindings;
export 'src/coding/coding.dart' show provideCoding;
export 'src/coding/runtime/code_run_request.dart'
    show CodeBindingFn, CodeBindingNamespace, CodeRunLimits, CodeRunRequest;
export 'src/coding/runtime/code_run_result.dart'
    show CodeRunFailure, CodeRunFailureKind, CodeRunResult;
export 'src/coding/runtime/code_runtime.dart' show CodeRuntime;
export 'src/coding/runtime/subprocess_runtime.dart' show SubprocessCodeRuntime;
export 'src/coding/tools/run_code_tool.dart' show RunCodeTool;
