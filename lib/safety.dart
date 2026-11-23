/// nava 工具层安全护栏：读后写 / 重复调用 / 敏感文件。
library;

export 'src/paths/canonical_path.dart'
    show canonicalToolPath, canonicalizeBestEffortPath, expandToolHome;
export 'src/safety/patch_paths.dart' show PatchTarget, patchTargets;
export 'src/safety/read_ledger.dart'
    show ReadLedger, ReadLedgerMiddleware, fileFingerprint;
export 'src/safety/write_guard.dart'
    show ReadBeforeWriteGuard, kWriteStaleReadCode, kWriteWithoutReadCode;
