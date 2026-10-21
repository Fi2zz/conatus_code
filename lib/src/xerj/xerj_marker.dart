/// 已索引标记：记录某个前缀至少成功索引过一次。
///
/// 自动刷新只在标记存在时启动，避免用户从未索引过时因为一次编辑就在后台
/// 跑全量索引。标记放在 XERJ 数据目录下，跨会话可见。
library;

import 'dart:io';

/// 按文件存在与否表达「已索引」。
class XerjMarker {
  const XerjMarker(this.file);

  /// 标记文件路径。
  final String file;

  /// 是否已索引过。
  Future<bool> marked() => File(file).exists();

  /// 写入标记（幂等覆盖）。
  Future<void> mark() async {
    final File target = File(file);
    await target.parent.create(recursive: true);
    await target.writeAsString(DateTime.now().toIso8601String());
  }
}
