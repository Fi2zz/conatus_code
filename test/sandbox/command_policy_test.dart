import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  late CommandPolicy policy;

  setUp(() {
    policy = CommandPolicy(root: '/tmp/cc-sb-root');
  });

  test('白名单外可执行 → deny', () {
    final CommandVerdict verdict = policy.decide('curl -s https://example.com');
    expect(verdict.decision, CommandDecision.deny);
    expect(verdict.reason, contains('白名单'));
  });

  test('rm -rf / → deny（shield 语义分析）', () {
    expect(policy.decide('rm -rf /').decision, CommandDecision.deny);
  });

  test('多命令（&&）→ review', () {
    expect(policy.decide('echo hi && git status').decision,
        CommandDecision.review);
  });

  test('命令替换 → review', () {
    expect(policy.decide(r'echo $(pwd)').decision, CommandDecision.review);
  });

  test('dart test → allow', () {
    expect(policy.decide('dart test').decision, CommandDecision.allow);
  });

  test('cat /etc/passwd → deny（越界绝对路径）', () {
    final CommandVerdict verdict = policy.decide('cat /etc/passwd');
    expect(verdict.decision, CommandDecision.deny);
    expect(verdict.reason, contains('越界'));
  });

  test('ls ~/.pub-cache → allow（只读放行）', () {
    expect(policy.decide('ls ~/.pub-cache').decision, CommandDecision.allow);
  });

  test('git status → allow', () {
    expect(policy.decide('git status').decision, CommandDecision.allow);
  });
}
