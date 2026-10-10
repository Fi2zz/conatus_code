/// E-16：启动警告不得污染 stdout——headless `--output-format json` 要求 stdout
/// 只有机器可解析的单行 JSON，其余提示一律走 stderr。
library;

import 'dart:async';
import 'dart:io';

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_code/tui.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

void main() {
  test('OAuth 未实现提示走 stderr，不写 stdout', () async {
    final Directory dir = Directory.systemTemp.createTempSync(
      'nava-oauth-warn',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final String sep = Platform.pathSeparator;
    final List<String> printedToStdout = <String>[];

    // print(...) 经 zone 的 print 落到 stdout；stderr.writeln 则不经过这里。
    await runZoned(
      () async {
        try {
          final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
            baseDir: dir.path,
            sessionDir: dir.path,
            memoryFile: '${dir.path}${sep}memory.json',
            webTools: false,
            skills: false,
            llm: FallbackLlm(const <LlmProvider>[]),
            providers: <ProviderConfig>[
              const ProviderConfig(
                name: 'oauth-only',
                baseUrl: 'https://example.com',
                oauthKey: 'tok',
              ),
            ],
            provider: 'oauth-only',
            interactive: false,
          );
          await runtime.dispose();
        } catch (_) {
          // 该 provider 本就没有可用的 api_key，装配后半程可能报错——
          // 本用例只关心「警告是否写到了 stdout」。
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => printedToStdout.add(line),
      ),
    );

    expect(
      printedToStdout.where((String line) => line.contains('OAuth')),
      isEmpty,
    );
  });
}
