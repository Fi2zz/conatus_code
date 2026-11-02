/// `nava plugin` 的用法文案。
library;

/// 用法。
const String kPluginUsage = '''
用法：nava plugin <子命令> [参数]
  add <目录|npm/git spec>   安装插件并写入 config.toml
  list                      列出全局插件与项目插件
  remove <spec> [--purge]   从 config.toml 移除；--purge 同时卸载包
  check                     预留（P4.2）
  update                    预留（P4.2）
  --config <路径>           目标 config.toml
  --workdir <路径>          项目插件发现起点
  --help                    显示本帮助

项目插件从 <workdir>/.opencode/plugins 与 opencode.json(c) 自动发现，
首次加载前会询问是否信任。''';
