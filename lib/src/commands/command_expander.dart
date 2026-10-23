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
/// [executor] 非空时直接以原始 [args] 调用，不做模板展开。否则先替换
/// 占位符、再执行 shell 块，最后在模板没有任何占位符时把非空参数追加到
/// 末尾（空行分隔）。shell 失败向上抛出，由调用方提示用户。
Future<String> expandCommand(
  CommandDefinition def,
  String args, {
  required Future<String> Function(String) runShell,
}) async {
  final Future<String> Function(String)? executor = def.executor;
  if (executor != null) return executor(args);
  final List<String> tokens = _tokenize(args);
  final String trimmed = args.trim();
  final bool hasPlaceholder = _placeholder.hasMatch(def.template);
  String result = _substitute(def.template, trimmed, tokens);
  result = await _runShellBlocks(result, runShell);
  if (!hasPlaceholder && trimmed.isNotEmpty) {
    result = result.isEmpty ? trimmed : '$result\n\n$trimmed';
  }
  return result;
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
List<String> _tokenize(String args) => _argument
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

/// 顺序执行 shell 块；输出原样插入且不再参与占位符展开。
Future<String> _runShellBlocks(
  String template,
  Future<String> Function(String) runShell,
) async {
  final StringBuffer output = StringBuffer();
  int last = 0;
  for (final RegExpMatch match in _shellBlock.allMatches(template)) {
    output.write(template.substring(last, match.start));
    final String command = match.group(1)!.trim();
    if (command.isEmpty) {
      last = match.end;
      continue;
    }
    output.write(_truncate((await runShell(command)).trim()));
    last = match.end;
  }
  output.write(template.substring(last));
  return output.toString();
}

String _truncate(String text) => text.length <= kCommandShellOutputLimit
    ? text
    : text.substring(0, kCommandShellOutputLimit);
