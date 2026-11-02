/// 在每条 shell 请求上追加插件环境变量。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

/// 包装 [ShellExecutor]，把 [env] 合并进每次执行的规格。
class PluginEnvShell implements ShellExecutor {
  PluginEnvShell({required this.inner, required this.env});

  final ShellExecutor inner;
  final Map<String, String> env;

  @override
  ShellExecSpec resolve(ShellExecRequest request) {
    final ShellExecSpec spec = inner.resolve(request);
    return ShellExecSpec(
      command: spec.command,
      workdir: spec.workdir,
      timeoutMs: spec.timeoutMs,
      stdoutMaxBytes: spec.stdoutMaxBytes,
      stdin: spec.stdin,
      env: <String, String>{...?spec.env, ...env},
      cancelSignal: spec.cancelSignal,
    );
  }

  @override
  Future<ShellRunResult> run(ShellExecSpec spec) => inner.run(spec);

  @override
  Future<ShellProcess> start(ShellExecSpec spec) => inner.start(spec);
}
