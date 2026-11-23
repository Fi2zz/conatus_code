/// nava 工具层安全护栏：读后写 / 重复调用 / 敏感文件。
library;

export 'src/paths/canonical_path.dart'
    show canonicalToolPath, canonicalizeBestEffortPath, expandToolHome;
