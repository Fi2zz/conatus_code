/// 待通报队列：人的编辑（watcher 登记的 human 补丁）生成摘要通报，
/// 由 SteeringSource 在组下一次模型请求前随排队消息一起注入会话——
/// 「diff 即反馈」闭环（设计文档 §2.4）。
///
/// 通报形态是摘要 + 每文件 +/- 行数，不带全文：模型要细节自己会
/// read_file（对齐 tool_result_eviction 的「预览 + 路径」哲学）。
library;

/// 待通报队列（会话级临时态，不落盘；服务键 `'storyNotices'`）。
class StoryNotices {
  final List<String> _notices = <String>[];

  /// 待通报条数。
  int get length => _notices.length;

  /// 追加一条通报。
  void add(String notice) => _notices.add(notice);

  /// 取回全部通报并清空队列。
  List<String> drain() {
    final List<String> out = List<String>.of(_notices);
    _notices.clear();
    return out;
  }
}

/// 一次人的文件变化（通报渲染的输入）。
typedef StoryFileChange = ({String path, int added, int removed});

/// 行级变化：逐行等值对齐，其余算增删（简单行级对比，不上 diff 算法）。
({int added, int removed}) diffLines(String oldText, String newText) {
  final List<String> oldLines = oldText.isEmpty
      ? const <String>[]
      : oldText.split('\n');
  final List<String> newLines = newText.isEmpty
      ? const <String>[]
      : newText.split('\n');
  final int common = oldLines.length < newLines.length
      ? oldLines.length
      : newLines.length;
  int same = 0;
  for (int i = 0; i < common; i++) {
    if (oldLines[i] == newLines[i]) same++;
  }
  return (added: newLines.length - same, removed: oldLines.length - same);
}

/// 渲染人的编辑通报：事实通报而非新任务指令（它作为 user 消息进会话）。
String renderEditNotice(List<StoryFileChange> changes) {
  final String files = changes
      .map((StoryFileChange c) => '${c.path}（+${c.added}/-${c.removed} 行）')
      .join('、');
  return '（你在 AI 工作途中修改了文件：$files；需要细节用 read_file 读取）';
}
