/// XERJ 代码检索工具包：code_search / find_definition / index_project。
///
/// XERJ 是可选外部二进制（<https://xerj.org>），不可用时工具静默不注册。
///
/// **实验性**：API 可能在没有 major 版本变更的情况下调整，勿在生产环境依赖。
library;

export 'src/xerj/xerj.dart' show XerjOptions, provideXerjSearch;
export 'src/xerj/xerj_auto_indexer.dart' show XerjAutoIndexer, kXerjWriteTools;
export 'src/xerj/xerj_binary.dart' show XerjBinary;
export 'src/xerj/xerj_endpoint.dart'
    show XerjEndpoint, XerjHealthProbe, XerjProcess, XerjProcessStarter;
export 'src/xerj/xerj_exec.dart' show XerjExec;
export 'src/xerj/xerj_marker.dart' show XerjMarker;
export 'src/xerj/xerj_node.dart' show XerjNode;
export 'src/xerj/xerj_tools.dart'
    show CodeSearchTool, FindDefinitionTool, IndexProjectTool;
