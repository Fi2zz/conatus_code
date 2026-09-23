/// TUI 附件：粘贴/拖放进入输入栏的图片与文件。
///
/// 粘贴文本里识别出的文件路径（终端拖放产生）在这里登记为附件；提交时图片
/// 读字节转为 [LlmImage]，文本文件内联为 `<file>` 块（与 @ 引用同格式）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_llm/conatus_llm.dart';

/// 单图大小上限（字节）。
const int kAttachmentImageMaxBytes = 4 * 1024 * 1024;

/// 非图片（文本）附件内联上限，与 @ 引用一致（字节）。
const int kAttachmentFileMaxBytes = 200 * 1024;

/// 一次提交最多携带的附件数。
const int kAttachmentMaxCount = 8;

/// 图片扩展名 → MIME 类型。
const Map<String, String> kImageMimes = <String, String>{
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
};

/// 一条待发送的附件（文件已存在于磁盘）。
class TuiAttachment {
  const TuiAttachment({required this.path, required this.mimeType});

  /// 附件文件绝对路径。
  final String path;

  /// MIME 类型（按扩展名推断）。
  final String mimeType;

  /// 是否图片（作为多模态 parts 发送；否则内联文本）。
  bool get isImage => mimeType.startsWith('image/');

  /// 文件名（用于屏上展示）。
  String get name => path.split(Platform.pathSeparator).last;
}

/// 附件物化结果：随消息发送的图片与内联文本块。
class AttachmentMaterialization {
  const AttachmentMaterialization({
    required this.images,
    required this.inlineText,
  });

  /// 图片附件（base64）。
  final List<LlmImage> images;

  /// 文本附件拼接出的 `<file>` 块。
  final String inlineText;
}

/// 按扩展名推断 MIME；不认识时按纯文本处理。
String mimeFromPath(String path) {
  final String ext = path.split('.').last.toLowerCase();
  return kImageMimes[ext] ?? 'text/plain';
}

/// 从粘贴文本中识别文件路径附件。
///
/// 只有当全部非空 token 都对应到存在的文件时才返回附件列表；含普通文本、
/// 混合内容或超过数量上限时返回空（按普通文本粘贴处理）。相对路径以
/// [cwd] 为基准解析。
List<TuiAttachment> extractPathAttachments(String pastedText, String cwd) {
  final List<String> tokens = pastedText
      .split(RegExp(r'[\r\n]+'))
      .expand((String line) => line.split('\t'))
      .map(_cleanToken)
      .where((String token) => token.isNotEmpty)
      .toList();
  if (tokens.isEmpty || tokens.length > kAttachmentMaxCount) {
    return const <TuiAttachment>[];
  }
  final List<TuiAttachment> found = <TuiAttachment>[];
  for (final String token in tokens) {
    final String path = _resolvePath(token, cwd);
    if (!File(path).existsSync()) return const <TuiAttachment>[];
    found.add(TuiAttachment(path: path, mimeType: mimeFromPath(path)));
  }
  return found;
}

/// 附件物化：图片 → [LlmImage]（超限抛 [StateError]）；文本 → `<file>` 块。
Future<AttachmentMaterialization> materializeAttachments(
  List<TuiAttachment> attachments,
) async {
  final List<LlmImage> images = <LlmImage>[];
  final StringBuffer inline = StringBuffer();
  for (final TuiAttachment attachment in attachments) {
    final List<int> bytes = await File(attachment.path).readAsBytes();
    if (attachment.isImage) {
      if (bytes.length > kAttachmentImageMaxBytes) {
        throw StateError('图片 ${attachment.name} 超过 4MB 上限');
      }
      images.add(LlmImage(
        mimeType: attachment.mimeType,
        base64Data: base64Encode(bytes),
      ));
      continue;
    }
    if (bytes.length > kAttachmentFileMaxBytes) {
      throw StateError('文件 ${attachment.name} 超过 200KB 上限');
    }
    final String content = utf8.decode(bytes, allowMalformed: true);
    inline.write('<file path="${attachment.path}">\n$content\n</file>\n');
  }
  return AttachmentMaterialization(images: images, inlineText: inline.toString());
}

/// 去掉引号与空白。
String _cleanToken(String raw) => raw.trim().replaceAll('"', '').replaceAll("'", '');

/// 解析 token：去 `file://` 前缀；相对路径拼 [cwd]。
String _resolvePath(String token, String cwd) {
  String path = token;
  const String scheme = 'file://';
  if (path.startsWith(scheme)) path = path.substring(scheme.length);
  if (path.startsWith('/')) return path;
  return '$cwd/$path';
}

/// 输入框占位标记与附件序号的提取结果。
class AttachmentRefs {
  const AttachmentRefs({required this.text, required this.indices});

  /// 移除占位标记后的正文。
  final String text;

  /// 占位里的附件序号（按出现顺序去重，1 起）。
  final List<int> indices;
}

/// 附件占位标记：图片 `[image #N (宽×高)]`，非图片 `[file #N (文件名)]`。
///
/// 尺寸从文件字节解析（PNG/JPEG 头）；读不到时省略尺寸段。
String attachmentPlaceholder(TuiAttachment attachment, int index) {
  if (!attachment.isImage) {
    return '[file #$index (${attachment.name})]';
  }
  try {
    final List<int> bytes = File(attachment.path).readAsBytesSync();
    final String? dims = imageDimensions(bytes);
    return dims == null ? '[image #$index]' : '[image #$index ($dims)]';
  } on FileSystemException {
    return '[image #$index]';
  }
}

/// 从输入框正文提取附件占位：返回去除占位后的正文与附件序号列表。
/// 占位连同紧邻的前导空格一起移除，剩余空白压缩为单空格。
AttachmentRefs extractAttachmentRefs(String text) {
  final RegExp pattern =
      RegExp(r' ?\[(?:image|file) #(\d+)(?: \([^)]*\))?\]');
  final List<int> indices = <int>[];
  final String clean = text.replaceAllMapped(pattern, (Match match) {
    final int index = int.parse(match.group(1)!);
    if (!indices.contains(index)) {
      indices.add(index);
    }
    return '';
  });
  return AttachmentRefs(
    text: clean.trim().replaceAll(RegExp(r' {2,}'), ' '),
    indices: indices,
  );
}

/// 从图片字节解析 `宽×高`（PNG / JPEG 头）；其他格式或解析失败返回 `null`。
String? imageDimensions(List<int> bytes) {
  if (bytes.length >= 24 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return '${_be32(bytes, 16)}×${_be32(bytes, 20)}';
  }
  if (bytes.length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return _jpegDimensions(bytes);
  }
  return null;
}

/// JPEG：扫描段至 SOF0/SOF1/SOF2，读高（+5）宽（+7）。
String? _jpegDimensions(List<int> bytes) {
  int offset = 2;
  while (offset + 9 < bytes.length) {
    if (bytes[offset] != 0xFF) {
      offset++;
      continue;
    }
    final int marker = bytes[offset + 1];
    if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
      return '${_be16(bytes, offset + 7)}×${_be16(bytes, offset + 5)}';
    }
    final int length = _be16(bytes, offset + 2);
    if (length < 2) {
      return null;
    }
    offset += 2 + length;
  }
  return null;
}

int _be16(List<int> bytes, int offset) =>
    (bytes[offset] << 8) | bytes[offset + 1];

int _be32(List<int> bytes, int offset) =>
    _be16(bytes, offset) << 16 | _be16(bytes, offset + 2);
