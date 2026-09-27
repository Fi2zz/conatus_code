/// 单文件检查点归档：整个检查点压缩成一个 `.gz` 文件。
///
/// 格式：`gzip(header + entries)`，header 是清单 JSON + `\n`，entries 为
/// `[pathLen u32BE][path utf8][contentLen u64BE][content bytes]` 重复段。
/// 路径不含 NUL，长度前缀保证无歧义；文件内容以压缩后的二进制存在，**不以
/// 明文呈现**。**文件名是确定性哈希**（`sha256("<会话>:<轮次>")` 前 16 位），
/// 不可读、不暴露轮次时间线；轮次只记录在归档头部与 `index` 索引里。
/// `dart:io` 内置 GZipCodec，零额外依赖。
///
/// 读写都走流式（[CheckpointArchiveWriter] / [readCheckpointEntries]）：
/// 清单头先行，条目按 chunk 过 gzip 管道，内存占用 O(chunk) 而非 O(工作区)
/// —— base 快照/恢复不再整包缓冲（大工作区曾因此吃满内存、卡住会话加载）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'checkpoint_types.dart';

/// 一个归档条目（写路径）。
typedef CheckpointArchiveEntry = (String path, List<int> bytes);

/// 检查点归档的**不可读文件名**（`sha256("<会话>:<轮次>")` 前 16 位，**无扩展名**，
/// 看不出是 gzip 压缩、也不暴露轮次时间线；确定性、跨会话不同）。
String checkpointArchiveName(String sessionId, int turn) =>
    sha256.convert(utf8.encode('$sessionId:$turn')).toString().substring(0, 16);

/// 流式归档写入器：构造时写清单头（gzip 流内），随后逐条目写入
/// （[addBytes] 写内存字节；[addFile] 按 chunk 读文件），[close] 收尾落盘。
/// 输出格式与 [readCheckpointArchive] 完全兼容。
class CheckpointArchiveWriter {
  CheckpointArchiveWriter(File target, CheckpointManifest manifest)
    : _controller = StreamController<List<int>>() {
    target.parent.createSync(recursive: true);
    _done = _controller.stream.transform(gzip.encoder).pipe(target.openWrite());
    _controller
      ..add(utf8.encode(jsonEncode(manifest.toJson())))
      ..add(<int>[0x0a]);
  }

  final StreamController<List<int>> _controller;
  late final Future<dynamic> _done;

  /// 写入一个内存中已有字节的条目。
  void addBytes(String path, List<int> bytes) {
    _writeFrameHeader(path, bytes.length);
    _controller.add(bytes);
  }

  /// 写入一个文件条目：长度前缀取自 [File.lengthSync]，内容按 chunk 流式读入。
  Future<void> addFile(String path, File file) async {
    _writeFrameHeader(path, file.lengthSync());
    await _controller.addStream(file.openRead());
  }

  /// 关闭 gzip 管道并落盘；之后不可再写。
  Future<void> close() async {
    await _controller.close();
    await _done;
  }

  void _writeFrameHeader(String path, int contentLen) {
    final List<int> pathBytes = utf8.encode(path);
    final ByteData lens = ByteData(12)
      ..setUint32(0, pathBytes.length)
      ..setUint64(4, contentLen);
    _controller.add(lens.buffer.asUint8List());
    _controller.add(pathBytes);
  }
}

/// 写一个检查点归档文件（覆盖）。内存中条目走 [CheckpointArchiveWriter]
/// 的便捷封装；大条目请直接用 writer 的 [CheckpointArchiveWriter.addFile]。
Future<void> writeCheckpointArchive(
  File target,
  CheckpointManifest manifest,
  List<CheckpointArchiveEntry> entries,
) async {
  final CheckpointArchiveWriter writer = CheckpointArchiveWriter(
    target,
    manifest,
  );
  for (final (String path, List<int> bytes) in entries) {
    writer.addBytes(path, bytes);
  }
  await writer.close();
}

/// 只读归档头部的清单：流式解压首行后即取消订阅，不整包解压。
///
/// base 归档可达数百 MB，而 `list()` / 差量快照每轮只要清单——整包解压曾
/// 让大工作区每轮口吃数秒、内存翻倍。
Future<CheckpointManifest> readCheckpointManifest(File file) async {
  final Stream<String> lines = file
      .openRead()
      .transform(gzip.decoder)
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  final String header;
  try {
    header = await lines.first;
  } on StateError {
    throw const CheckpointException('bad-archive', '检查点归档缺少清单头');
  }
  return CheckpointManifest.fromJson(
    jsonDecode(header) as Map<String, Object?>,
  );
}

/// 流式读出归档的全部条目：逐帧解析、逐条产出，不整包解压。
/// 单条目内容仍一次性物化（恢复按条目写盘），内存 ≈ 最大单文件而非全归档。
Stream<CheckpointArchiveEntry> readCheckpointEntries(File file) async* {
  final List<int> buffer = <int>[];
  bool headerSkipped = false;
  int offset = 0;
  await for (final List<int> chunk in file.openRead().transform(gzip.decoder)) {
    buffer.addAll(chunk);
    if (!headerSkipped) {
      final int nl = buffer.indexOf(0x0a, offset);
      if (nl < 0) continue;
      offset = nl + 1;
      headerSkipped = true;
    }
    while (_frameComplete(buffer, offset)) {
      final int pathLen = _u32(buffer, offset);
      final int contentLen = _u64(buffer, offset + 4);
      final int pathStart = offset + 12;
      final int contentStart = pathStart + pathLen;
      final int end = contentStart + contentLen;
      final String path = utf8.decode(buffer.sublist(pathStart, contentStart));
      final List<int> content = Uint8List.fromList(
        buffer.sublist(contentStart, end),
      );
      offset = end;
      yield (path, content);
    }
    if (offset > 0) {
      buffer.removeRange(0, offset);
      offset = 0;
    }
  }
}

bool _frameComplete(List<int> buffer, int offset) {
  if (buffer.length - offset < 12) return false;
  final int pathLen = _u32(buffer, offset);
  final int contentLen = _u64(buffer, offset + 4);
  return buffer.length - offset >= 12 + pathLen + contentLen;
}

int _u32(List<int> buffer, int offset) =>
    (buffer[offset] << 24) |
    (buffer[offset + 1] << 16) |
    (buffer[offset + 2] << 8) |
    buffer[offset + 3];

int _u64(List<int> buffer, int offset) {
  int value = 0;
  for (int i = 0; i < 8; i++) {
    value = value * 256 + buffer[offset + i];
  }
  return value;
}

/// 读一个检查点归档：返回清单与全部条目（整包解压）。
///
/// 保留用于兼容与测试；生产路径请用 [readCheckpointManifest] /
/// [readCheckpointEntries]（流式）。gzip 非随机访问，整读是它们的旧实现。
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
    json =
        jsonDecode(utf8.decode(gzip.decode(index.readAsBytesSync())))
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
  index.writeAsBytesSync(
    gzip.encode(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'turns': <Map<String, Object?>>[
            for (final CheckpointInfo info in infos)
              <String, Object?>{'turn': info.turn, 'files': info.files},
          ],
        }),
      ),
    ),
  );
}
