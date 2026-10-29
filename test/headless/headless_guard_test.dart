/// headless 审批语义提示：always_ask / 缺省档在无人应答时的实际后果。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  group('headlessAskNotice', () {
    test('headless + 缺省 ask_when_needed → 提示高风险工具会被拒', () {
      final String? notice = headlessAskNotice(
        headless: true,
        approval: const ApprovalConfig(),
      );

      expect(notice, isNotNull);
      expect(notice, contains('PERMISSION_ASK_UNATTENDED'));
      expect(notice, contains('never_ask'));
    });

    test('never_ask / TUI → 不提示', () {
      expect(
        headlessAskNotice(
          headless: true,
          approval: const ApprovalConfig(mode: ApprovalMode.neverAsk),
        ),
        isNull,
      );
      expect(
        headlessAskNotice(headless: false, approval: const ApprovalConfig()),
        isNull,
      );
    });
  });

  group('approvalModeIgnoredNotice', () {
    test('headless + always_ask → 提示会直接拒绝需要确认的工具', () {
      final String? notice = approvalModeIgnoredNotice(
        headless: true,
        approval: const ApprovalConfig(mode: ApprovalMode.alwaysAsk),
      );

      expect(notice, isNotNull);
      expect(notice, contains('always_ask'));
      expect(notice, contains('拒绝'));
      expect(notice, contains('PERMISSION_ASK_UNATTENDED'));
    });

    test('headless + 缺省/never_ask → 不打扰', () {
      expect(
        approvalModeIgnoredNotice(
          headless: true,
          approval: const ApprovalConfig(),
        ),
        isNull,
      );
      expect(
        approvalModeIgnoredNotice(
          headless: true,
          approval: const ApprovalConfig(mode: ApprovalMode.neverAsk),
        ),
        isNull,
      );
    });

    test('TUI 模式 → 不提示（审批链正常生效）', () {
      expect(
        approvalModeIgnoredNotice(
          headless: false,
          approval: const ApprovalConfig(mode: ApprovalMode.alwaysAsk),
        ),
        isNull,
      );
    });
  });
}
