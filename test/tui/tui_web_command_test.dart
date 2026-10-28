/// `/web`：搜索源状态。
library;

import 'package:conatus_code/tui.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_search/conatus_search.dart';
import 'package:test/test.dart';

class _Provider implements SearchProvider {
  _Provider(this.name, {this.fails = false});

  @override
  final String name;
  final bool fails;

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async {
    if (fails) throw const SearchException('boom');
    return const <SearchResult>[];
  }
}

Future<ConatusTuiController> _controller({bool search = true}) async {
  final Context app = Context.root();
  addTearDown(app.dispose);
  provideTools(app);
  provideLlm(app, llm: FallbackLlm(const <LlmProvider>[]));
  final SessionStore sessions = provideSessions(app);
  if (search) {
    provideSearch(
      app,
      providers: <SearchProvider>[
        _Provider('ok'),
        _Provider('bad', fails: true),
      ],
    );
  }
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    initialSession: 'web',
    modelLabel: 'mock',
    onExit: () {},
  );
  await controller.start();
  return controller;
}

void main() {
  test('/web 展示搜索源', () async {
    final ConatusTuiController controller = await _controller();

    await controller.handleLine('/web');

    final String text = controller.transcript.messages.last.text;
    expect(text, contains('ok'));
    expect(text, contains('bad'));
    controller.dispose();
  });

  test('未装配搜索时提示', () async {
    final ConatusTuiController controller = await _controller(search: false);

    await controller.handleLine('/web');

    expect(controller.transcript.messages.last.text, contains('搜索未装配'));
    controller.dispose();
  });
}
