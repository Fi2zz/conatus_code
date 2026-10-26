/// JSONC（带注释与尾随逗号的 JSON）解码：OpenCode 配置使用这种格式。
library;

import 'dart:convert';

/// 去除 JSONC 注释与尾随逗号后交给 [jsonDecode]。
///
/// 字符串内的 `//`、`/*` 与逗号原样保留；注释字符被替换成空格以保留大致
/// 位置（错误信息里的列号不会严重偏移）。
Object? decodeJsonc(String text) => jsonDecode(stripJsonc(text));

/// 去注释与尾随逗号，返回标准 JSON 文本。
String stripJsonc(String text) {
  final String withoutComments = _stripComments(text);
  return _stripTrailingCommas(withoutComments);
}

String _stripComments(String text) {
  final StringBuffer out = StringBuffer();
  bool inString = false;
  bool escaped = false;
  for (int index = 0; index < text.length; index++) {
    final String char = text[index];
    if (inString) {
      out.write(char);
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }
    if (char == '"') {
      inString = true;
      out.write(char);
      continue;
    }
    if (char == '/' && index + 1 < text.length) {
      final String next = text[index + 1];
      if (next == '/') {
        index = _skipLineComment(text, index);
        out.write('\n');
        continue;
      }
      if (next == '*') {
        index = _skipBlockComment(text, index);
        out.write(' ');
        continue;
      }
    }
    out.write(char);
  }
  return out.toString();
}

int _skipLineComment(String text, int start) {
  int index = start + 2;
  while (index < text.length && text[index] != '\n') {
    index++;
  }
  return index;
}

int _skipBlockComment(String text, int start) {
  int index = start + 2;
  while (index + 1 < text.length) {
    if (text[index] == '*' && text[index + 1] == '/') return index + 1;
    index++;
  }
  return text.length;
}

String _stripTrailingCommas(String text) {
  final StringBuffer out = StringBuffer();
  bool inString = false;
  bool escaped = false;
  for (int index = 0; index < text.length; index++) {
    final String char = text[index];
    if (inString) {
      out.write(char);
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }
    if (char == '"') {
      inString = true;
      out.write(char);
      continue;
    }
    if (char == ',') {
      final int next = _nextNonSpace(text, index + 1);
      if (next < text.length && (text[next] == '}' || text[next] == ']')) {
        continue;
      }
    }
    out.write(char);
  }
  return out.toString();
}

/// [start] 之后第一个非空白字符的下标；越界返回 `text.length`。
int _nextNonSpace(String text, int start) {
  int index = start;
  while (index < text.length && _isSpace(text[index])) {
    index++;
  }
  return index;
}

bool _isSpace(String char) =>
    char == ' ' || char == '\t' || char == '\n' || char == '\r';
