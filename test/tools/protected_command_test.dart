/// `.opencode` 命令级兜底检查的单元测试。
///
/// 这是 best-effort：真正的边界是 Seatbelt 的 `deny file-write*`（见
/// `sandbox_integration_test.dart`）。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  group('readOnlyCommandViolation', () {
    for (final String command in <String>[
      'echo x > .opencode/x',
      'echo x >> .opencode/x',
      'printf x | tee -a .opencode/x',
      'rm -rf .opencode',
      'rm .opencode/commands/x.md',
      'mv a.txt .opencode/a.txt',
      'cp a.txt .opencode/a.txt',
      'sed -i s/a/b/ .opencode/commands/x.md',
      'truncate -s 0 .opencode/x',
      'touch .opencode/x',
      'mkdir -p .opencode/agents',
      'sh -c "echo x > .opencode/x"',
      'echo x > /abs/work/.opencode/x',
      'echo x 2>.opencode/x',
      'rm -rf ~/.config/opencode',
      'echo x > ~/.config/opencode/x',
      'cp a.txt \$HOME/.config/opencode/a.txt',
      'sed -i s/a/b/ /Users/u/.config/opencode/opencode.json',
      'rm -rf .OPENCODE',
    ]) {
      test('拒绝写类命令：$command', () {
        expect(readOnlyCommandViolation(command), kReadOnlyCommandMessage);
      });
    }

    for (final String command in <String>[
      'cat .opencode/commands/x.md',
      'ls -la .opencode',
      'rg TODO .opencode',
      'cat ~/.config/opencode/opencode.json',
      'echo hello > out.txt',
      'git status',
      'cp my.opencode.txt other.txt',
      'echo .opencode-backup/x',
      'cmp .opencode/a .opencode/b',
    ]) {
      test('放行读类 / 无关命令：$command', () {
        expect(readOnlyCommandViolation(command), isNull);
      });
    }
  });
}
