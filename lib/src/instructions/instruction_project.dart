/// 项目层与全局层的待读文件清单。
library;

import 'dart:io';

import 'instruction_paths.dart';

/// 项目层每个目录读取的文件名（顺序即拼接顺序）。
const List<String> kInstructionFileNames = <String>['AGENTS.md', 'NAVA.md'];

/// 全局层待读文件：`~/.nava/AGENTS.md` → `~/.config/opencode/AGENTS.md`。
List<String> globalInstructionPaths(String? home, bool enabled) {
  if (!enabled || home == null) return const <String>[];
  final String sep = Platform.pathSeparator;
  return <String>[
    joinInstructionPath(home, '.nava${sep}AGENTS.md'),
    joinInstructionPath(home, '.config${sep}opencode${sep}AGENTS.md'),
  ];
}

/// 项目层待读文件：项目根到工作目录逐层，每层 AGENTS.md / NAVA.md。
///
/// 祖先层不在工作区内，按 `direct` 模式只接受普通文件（禁止符号链接重定向）；
/// 工作目录内的层仍按工作目录 jail 校验。
List<ProjectInstructionFile> projectInstructionFiles(
  String workdir,
  String? home,
) {
  final String root = findProjectRoot(workdir, home);
  return <ProjectInstructionFile>[
    for (final String dir in projectChain(root, workdir))
      for (final String name in kInstructionFileNames)
        ProjectInstructionFile(
          joinInstructionPath(dir, name),
          isWithinWorkdir(dir, workdir) ? workdir : null,
          direct: !isWithinWorkdir(dir, workdir),
        ),
  ];
}

/// 一个项目层待读文件及其越界校验方式。
class ProjectInstructionFile {
  const ProjectInstructionFile(this.path, this.root, {required this.direct});

  final String path;

  /// 非 `null` 时 canonical 路径必须落在该根内。
  final String? root;

  /// 是否要求不走符号链接（项目祖先层的文件）。
  final bool direct;
}
