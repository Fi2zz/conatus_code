import 'dart:io';

import 'package:conatus_code/src/tui/system_notifier.dart';
import 'package:conatus_cron/conatus_cron.dart';
import 'package:test/test.dart';

void main() {
  test('systemCronNotifier 只在 macOS / Linux 非 null', () {
    final CronNotifier? notifier = systemCronNotifier();
    if (Platform.isMacOS || Platform.isLinux) {
      expect(notifier, isNotNull);
    } else {
      expect(notifier, isNull);
    }
  });
}
