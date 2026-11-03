/// `StartupTiming`：启动各阶段耗时采样与 `/doctor` 文案。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

void main() {
  test('四个里程碑齐全：总耗时与三段明细', () {
    Duration fake = Duration.zero;
    final StartupTiming timing = StartupTiming(now: () => fake);
    fake = const Duration(milliseconds: 38);
    timing.markConfigLoaded();
    fake = const Duration(milliseconds: 358);
    timing.markRuntimeReady();
    fake = const Duration(milliseconds: 412);
    timing.markFirstFrame();

    expect(timing.describe(), '总 412ms（配置 38 · 装配 320 · 首帧 54）');
  });

  test('没有首帧（headless / 库用法）：降级标注未记录', () {
    Duration fake = Duration.zero;
    final StartupTiming timing = StartupTiming(now: () => fake);
    fake = const Duration(milliseconds: 38);
    timing.markConfigLoaded();
    fake = const Duration(milliseconds: 358);
    timing.markRuntimeReady();

    expect(timing.describe(), '总 358ms（配置 38 · 装配 320；首帧未记录）');
  });

  test('一个里程碑都没打：未采集', () {
    final StartupTiming timing = StartupTiming(now: () => Duration.zero);

    expect(timing.describe(), '未采集');
  });

  test('只到配置装载：后续阶段标注未记录', () {
    Duration fake = Duration.zero;
    final StartupTiming timing = StartupTiming(now: () => fake);
    fake = const Duration(milliseconds: 38);
    timing.markConfigLoaded();

    expect(timing.describe(), '总 38ms（配置 38；装配、首帧未记录）');
  });
}
