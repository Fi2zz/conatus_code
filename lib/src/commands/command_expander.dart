/// 命令模板展开：`$ARGUMENTS` / `$1..$9` 占位符与 `!` shell 块。
library;

import 'command_definition.dart';

/// 单个 shell 块插入内容的最大字符数。
const int kCommandShellOutputLimit = 8000;

final RegExp _placeholder = RegExp(r'\$(ARGUMENTS|[1-9])');
final RegExp _shellBlock = RegExp(r'!`([^`]*)`');
final RegExp _argument = RegExp(r'''"[^"]*"?|'[^']*'?|[^\s"']+''');

/// 展开一条命令。
///
/// [executor] 非空时直接以原始 [args] 调用，不做模板展开。否则**先按模板
/// 执行 shell 块、再替换占位符**：shell 块只识别模板本身，参数文本里即使
/// 含有 ``!`…` `` 也只会原样插入，绝不执行；shell 块内的 `$1` / `$ARGUMENTS`
/// 同样不展开（命令文本在替换前取出），shell 输出也不会被二次展开。
/// 模板没有任何占位符时，非空参数追加到末尾（空行分隔）。shell 失败向上
/// 抛出，由调用方提示用户。
Future<String> expandCommand(
  CommandDefinition def,
  String args, {
  required Future<String> Function(String) runShell,
}) async {
  final Future<String> Function(String)? executor = def.executor;
  if (executor != null) return executor(args);
  final List<String> tokens = tokenizeCommandArguments(args);
  final String trimmed = args.trim();
  final bool placeholderPresent = _placeholder.hasMatch(def.template);
  final String result = await _expandTemplate(
    def.template,
    trimmed,
    tokens,
    runShell,
  );
  if (!placeholderPresent && trimmed.isNotEmpty) {
    return result.isEmpty ? trimmed : '$result\n\n$trimmed';
  }
  return result;
}

/// 单遍处理模板：文本片段替换占位符，shell 块执行后原样插入。
Future<String> _expandTemplate(
  String template,
  String arguments,
  List<String> tokens,
  Future<String> Function(String) runShell,
) async {
  final StringBuffer output = StringBuffer();
  int last = 0;
  for (final RegExpMatch match in _shellBlock.allMatches(template)) {
    final String text = template.substring(last, match.start);
    output.write(_substitute(text, arguments, tokens));
    final String command = match.group(1)!.trim();
    if (command.isNotEmpty) {
      output.write(_truncate((await runShell(command)).trim()));
    }
    last = match.end;
  }
  final String tail = template.substring(last);
  output.write(_substitute(tail, arguments, tokens));
  return output.toString();
}

/// 占位符单遍替换，避免参数内容里的 `$1` 被二次展开。
String _substitute(String template, String arguments, List<String> tokens) =>
    template.replaceAllMapped(_placeholder, (Match match) {
      final String key = match.group(1)!;
      if (key == 'ARGUMENTS') return arguments;
      return _token(tokens, int.parse(key));
    });

String _token(List<String> tokens, int index) =>
    index <= tokens.length ? tokens[index - 1] : '';

/// 按空白分词，支持单/双引号分组；未闭合引号吞到参数末尾。
///
/// 动态命令（MCP prompt 等）按位置取参时复用同一套分词，保证 `"a b" 2` 的
/// 解析与模板 `$1` 一致。
List<String> tokenizeCommandArguments(String args) => _argument
    .allMatches(args)
    .map((RegExpMatch match) => _unquote(match.group(0)!))
    .toList();

/// 去掉成对（或未闭合的起始）引号。
String _unquote(String token) {
  final String quote = token.isEmpty ? '' : token[0];
  if (quote != '"' && quote != "'") return token;
  final bool closed = token.length > 1 && token.endsWith(quote);
  return closed ? token.substring(1, token.length - 1) : token.substring(1);
}

/// 按 rune 截断，避免切断代理对产生非法 UTF-16。
String _truncate(String text) {
  final Runes runes = text.runes;
  if (runes.length <= kCommandShellOutputLimit) return text;
  return String.fromCharCodes(runes.take(kCommandShellOutputLimit));
}
