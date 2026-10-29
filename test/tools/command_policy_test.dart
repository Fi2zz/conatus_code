import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  late CommandPolicy policy;

  setUp(() {
    policy = CommandPolicy();
  });

  test('简单命令 → allow', () {
    expect(policy.decide('ls -la').decision, CommandDecision.allow);
  });

  test('多命令（&&）→ review', () {
    expect(
      policy.decide('echo hi && git status').decision,
      CommandDecision.review,
    );
  });

  test('强制递归删除根 → deny', () {
    expect(policy.decide('rm -rf /').decision, CommandDecision.deny);
  });

  test('deny 带可读理由', () {
    expect(policy.decide('rm -rf /').reason, isNotEmpty);
  });
}
