/// headless 安全闸门（E-9）：沙箱关闭 + 无人值守拒绝启动、always_ask 提示。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

const SandboxSettings _sandboxOn = SandboxSettings();
const SandboxSettings _sandboxOff = SandboxSettings(enabled: false);
const SandboxSettings _sandboxDanger = SandboxSettings(
  preset: SandboxPreset.dangerFullAccess,
);

void main() {
  group('validateHeadlessSafety', () {
    test('headless + 沙箱照常 → 放行', () {
      expect(
        validateHeadlessSafety(
          headless: true,
          sandbox: _sandboxOn,
          allowUnsafe: false,
        ),
        isNull,
      );
    });

    test('TUI 模式（非 headless）→ 沙箱关着也放行（有审批链兜底）', () {
      expect(
        validateHeadlessSafety(
          headless: false,
          sandbox: _sandboxOff,
          allowUnsafe: false,
        ),
        isNull,
      );
      expect(
        validateHeadlessSafety(
          headless: false,
          sandbox: _sandboxDanger,
          allowUnsafe: false,
        ),
        isNull,
      );
    });

    test('headless + enabled=false → 拒绝，消息指明原因与放行方式', () {
      final String? message = validateHeadlessSafety(
        headless: true,
        sandbox: _sandboxOff,
        allowUnsafe: false,
      );

      expect(message, isNotNull);
      expect(message, contains('拒绝启动'));
      expect(message, contains('enabled = false'));
      expect(message, contains('--allow-unsafe-headless'));
    });

    test('headless + danger_full_access → 拒绝，消息指明 preset', () {
      final String? message = validateHeadlessSafety(
        headless: true,
        sandbox: _sandboxDanger,
        allowUnsafe: false,
      );

      expect(message, isNotNull);
      expect(message, contains('danger_full_access'));
    });

    test('显式 --allow-unsafe-headless → 放行', () {
      expect(
        validateHeadlessSafety(
          headless: true,
          sandbox: _sandboxOff,
          allowUnsafe: true,
        ),
        isNull,
      );
      expect(
        validateHeadlessSafety(
          headless: true,
          sandbox: _sandboxDanger,
          allowUnsafe: true,
        ),
        isNull,
      );
    });
  });

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

  group('sandboxDisabledReason', () {
    test('两种关闭方式都算关闭，照常生效返回 null', () {
      expect(sandboxDisabledReason(_sandboxOn), isNull);
      expect(sandboxDisabledReason(_sandboxOff), contains('enabled = false'));
      expect(
        sandboxDisabledReason(_sandboxDanger),
        contains('danger_full_access'),
      );
    });
  });
}
