/// 单文件检查点归档：整个检查点压缩成一个 `.gz` 文件。
///
/// 格式：`gzip(header + entries)`，header 是清单 JSON + `\n`，entries 为
/// `[pathLen u32BE][path utf8][contentLen u64BE][content bytes]` 重复段。
/// 路径不含 NUL，长度前缀保证无歧义；文件内容以压缩后的二进制存在，**不以
/// 明文呈现**。**文件名是确定性哈希**（`sha256("<会话>:<轮次>")` 前 16 位），
/// 不可读、不暴露轮次时间线；轮次只记录在归档头部与 `index` 索引里。
/// `dart:io` 内置 GZipCodec，零额外依赖。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'checkpoint_types.dart';

/// 一个归档条目（写路径）。
typedef CheckpointArchiveEntry = (String path, List<int> bytes);

/// 检查点归档的**不可读文件名**（`<sha256前16位>.gz`，确定性、跨会话不同）。
String checkpointArchiveName(String sessionId, int turn) {
  final String hash = sha256
      .convert(utf8.encode('$sessionId:$turn'))
      .toString()
      .substring(0, 16);
  return '$hash.gz';
}

/// 写一个检查点归档文件（覆盖）。
Future<void> writeCheckpointArchive(
  File target,
  CheckpointManifest manifest,
  List<CheckpointArchiveEntry> entries,
) async {
  final List<int> header = utf8.encode(jsonEncode(manifest.toJson()));
  final BytesBuilder builder = BytesBuilder();
  builder.add(header);
  builder.addByte(0x0a);
  for (final (String path, List<int> bytes) in entries) {
    final ByteData lens = ByteData(12);
    final List<int> pathBytes = utf8.encode(path);
    lens.setUint32(0, pathBytes.length);
    lens.setUint64(4, bytes.length);
    builder.add(lens.buffer.asUint8List());
    builder.add(pathBytes);
    builder.add(bytes);
  }
  target.parent.createSync(recursive: true);
  await target.writeAsBytes(gzip.encode(builder.toBytes()), flush: true);
}

/// 读一个检查点归档：返回清单与全部条目。
///
/// gzip 非随机访问，`list()` 场景也要整体解压（清单在头部，解析即弃条目）。
(CheckpointManifest, List<CheckpointArchiveEntry>) readCheckpointArchive(
  File file,
) {
  final List<int> raw = gzip.decode(file.readAsBytesSync());
  final int nl = raw.indexOf(0x0a);
  if (nl < 0) {
    throw const CheckpointException('bad-archive', '检查点归档缺少清单头');
  }
  final Map<String, Object?> json =
      jsonDecode(utf8.decode(raw.sublist(0, nl))) as Map<String, Object?>;
  final CheckpointManifest manifest = CheckpointManifest.fromJson(json);
  final List<CheckpointArchiveEntry> entries = <CheckpointArchiveEntry>[];
  final ByteData data = ByteData.sublistView(Uint8List.fromList(raw));
  int offset = nl + 1;
  while (offset < raw.length) {
    final int pathLen = data.getUint32(offset);
    final int contentLen = data.getUint64(offset + 4);
    final int pathStart = offset + 12;
    final int contentStart = pathStart + pathLen;
    final String path = utf8.decode(raw.sublist(pathStart, contentStart));
    entries.add((path, raw.sublist(contentStart, contentStart + contentLen)));
    offset = contentStart + contentLen;
  }
  return (manifest, entries);
}

/// 读会话检查点索引（gzip）；缺失或损坏返回 `null`。
List<CheckpointInfo>? readCheckpointIndex(File index) {
  if (!index.existsSync()) return null;
  final Map<String, Object?> json;
  try {
    json = jsonDecode(utf8.decode(gzip.decode(index.readAsBytesSync())))
        as Map<String, Object?>;
  } catch (_) {
    return null;
  }
  return <CheckpointInfo>[
    for (final Object? item
        in (json['turns'] as List<Object?>?) ?? const <Object?>[])
      if (item is Map)
        CheckpointInfo(
          turn: item['turn'] as int? ?? 0,
          files: item['files'] as int? ?? 0,
        ),
  ];
}

/// 写会话检查点索引（gzip）。
void writeCheckpointIndex(File index, List<CheckpointInfo> infos) {
  index.parent.createSync(recursive: true);
  index.writeAsBytesSync(gzip.encode(utf8.encode(jsonEncode(<String, Object?>{
    'turns': <Map<String, Object?>>[
      for (final CheckpointInfo info in infos)
        <String, Object?>{'turn': info.turn, 'files': info.files},
    ],
  }))));
}
