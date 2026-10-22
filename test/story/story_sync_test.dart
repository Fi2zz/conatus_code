/// 段落同步器：切分、块 id 规则、LCS 对齐、退化、往返一致。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_doc/conatus_doc.dart';
import 'package:test/test.dart';

DocumentState _fold(List<PatchOp> ops) => foldPatches(<DocPatch>[
  DocPatch(id: 'p1', author: PatchAuthor.ai, ops: ops),
]);

List<DocBlock> _blocks(String path, List<String> paras) {
  final List<DocBlock> out = <DocBlock>[];
  final Set<String> taken = <String>{};
  for (final String p in paras) {
    String id = paragraphBlockId(path, p);
    int suffix = 2;
    while (!taken.add(id)) {
      id = '${paragraphBlockId(path, p)}-$suffix';
      suffix++;
    }
    out.add(DocBlock(id: id, text: p));
  }
  return out;
}

void main() {
  group('splitParagraphs / renderFileText', () {
    test('空行切段；空文件返回空；往返一致', () {
      expect(splitParagraphs(''), isEmpty);
      expect(splitParagraphs('  \n  '), isEmpty);
      expect(splitParagraphs('一\n\n二\n\n\n三'), <String>['一', '二', '三']);
      const String text = '段一\n行二\n\n段二';
      final List<DocBlock> blocks = _blocks('a.md', splitParagraphs(text));
      expect(renderFileText(blocks), text);
      expect(normalizeParagraphText('一\n\n\n\n二'), '一\n\n二');
    });
  });

  group('块 id', () {
    test('同内容同 id（跨 rebuild 稳定）；重复段落加后缀去重', () {
      final String id = paragraphBlockId('a.md', '同一段话');
      expect(id, paragraphBlockId('a.md', '同一段话'));
      expect(id, startsWith('a.md#'));
      expect(id.length, 'a.md#'.length + 8);
      // 两个相同段插入：第一个保留/分配 base，第二个 -2。
      final List<PatchOp> ops = buildSyncOps(
        path: 'a.md',
        oldBlocks: const <DocBlock>[],
        newText: '同一段话\n\n同一段话',
      );
      expect(ops.length, 2);
      expect(ops[0].blockId, id);
      expect(ops[1].blockId, '${ops[0].blockId}-2');
    });
  });

  group('buildSyncOps 对齐', () {
    test('中间段修改：只产生该段的 remove + insert，其它段不动', () {
      final List<DocBlock> old = _blocks('a.md', <String>['头段', '中段', '尾段']);
      final List<PatchOp> ops = buildSyncOps(
        path: 'a.md',
        oldBlocks: old,
        newText: '头段\n\n中段改\n\n尾段',
      );

      expect(ops.length, 2);
      expect(ops[0], isA<RemoveBlockOp>());
      expect(ops[0].blockId, old[1].id);
      final InsertBlockOp insert = ops[1] as InsertBlockOp;
      expect(insert.text, '中段改');
      expect(insert.afterId, old[0].id); // 锚在前一个保留段
      // fold 后新内容就位（以旧块为底应用）。
      expect(renderFileText(_foldWithBase(old, ops).blocks), '头段\n\n中段改\n\n尾段');
    });

    test('插入新段：锚在前一个保留段；首段插入锚 anchorBefore', () {
      final List<DocBlock> old = _blocks('a.md', <String>['一', '三']);
      final List<PatchOp> ops = buildSyncOps(
        path: 'a.md',
        oldBlocks: old,
        newText: '一\n\n二\n\n三',
      );
      expect(ops.single, isA<InsertBlockOp>());
      expect((ops.single as InsertBlockOp).afterId, old[0].id);

      final List<PatchOp> head = buildSyncOps(
        path: 'a.md',
        oldBlocks: old,
        newText: '零\n\n一\n\n三',
        anchorBefore: 'other.md#xxxx0000',
      );
      expect((head.single as InsertBlockOp).afterId, 'other.md#xxxx0000');
    });

    test('删除段：只 remove 该段', () {
      final List<DocBlock> old = _blocks('a.md', <String>['一', '二', '三']);
      final List<PatchOp> ops = buildSyncOps(
        path: 'a.md',
        oldBlocks: old,
        newText: '一\n\n三',
      );
      expect(ops.single, isA<RemoveBlockOp>());
      expect(ops.single.blockId, old[1].id);
      final DocumentState folded = _foldWithBase(old, ops);
      expect(renderFileText(blocksOfFile(folded, 'a.md')), '一\n\n三');
    });

    test('多段混合（改 + 增 + 删）', () {
      final List<DocBlock> old = _blocks('a.md', <String>['甲', '乙', '丙']);
      final List<PatchOp> ops = buildSyncOps(
        path: 'a.md',
        oldBlocks: old,
        newText: '甲改\n\n丙\n\n丁',
      );
      // 甲改（remove+insert）、丙保留、丁新增。
      final DocumentState folded = _foldWithBase(old, ops);
      expect(renderFileText(blocksOfFile(folded, 'a.md')), '甲改\n\n丙\n\n丁');
    });

    test('超 512 段退化为 path#full 单块', () {
      final String big = List<String>.generate(
        600,
        (int i) => '段落 $i',
      ).join('\n\n');
      final List<PatchOp> ops = buildSyncOps(
        path: 'big.md',
        oldBlocks: const <DocBlock>[],
        newText: big,
      );
      expect(ops.single, isA<InsertBlockOp>());
      expect(ops.single.blockId, 'big.md#full');
      // 已有 full 块时 replace。
      final List<PatchOp> again = buildSyncOps(
        path: 'big.md',
        oldBlocks: <DocBlock>[DocBlock(id: 'big.md#full', text: big)],
        newText: '$big\n\n段落 600',
      );
      expect(again.single, isA<ReplaceBlockOp>());
      expect(again.single.blockId, 'big.md#full');
    });

    test('旧格式整块（id=path）与新段落对齐：remove 整块 + insert 各段', () {
      final List<DocBlock> old = <DocBlock>[
        const DocBlock(id: 'a.md', text: '一\n\n二'),
      ];
      final List<PatchOp> ops = buildSyncOps(
        path: 'a.md',
        oldBlocks: old,
        newText: '一\n\n二\n\n三',
      );
      expect(ops.first, isA<RemoveBlockOp>());
      expect(ops.first.blockId, 'a.md');
      expect(ops.whereType<InsertBlockOp>().length, 3);
      final DocumentState folded = _foldWithBase(old, ops);
      expect(renderFileText(blocksOfFile(folded, 'a.md')), '一\n\n二\n\n三');
    });
  });

  group('syncFileOps 锚点', () {
    test('新文件首段锚到路径序前一个文件的末块', () {
      final DocumentState state = _fold(const <PatchOp>[
        InsertBlockOp(blockId: 'a.md#aaaaaaaa', text: '甲'),
      ]);
      final List<PatchOp> ops = syncFileOps(
        state: state,
        path: 'b.md',
        newText: '乙',
      );
      expect((ops.single as InsertBlockOp).afterId, 'a.md#aaaaaaaa');
      // 无更早文件时锚 null（文档开头）。
      final List<PatchOp> first = syncFileOps(
        state: state,
        path: '0.md',
        newText: '零',
      );
      expect((first.single as InsertBlockOp).afterId, isNull);
    });
  });
}

/// 以 [base] 块为底应用 [ops] 后的文档状态。
DocumentState _foldWithBase(List<DocBlock> base, List<PatchOp> ops) {
  final List<DocBlock> blocks = List<DocBlock>.of(base);
  for (final PatchOp op in ops) {
    op.apply(blocks);
  }
  return DocumentState(blocks);
}
