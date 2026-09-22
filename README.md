# conatus_code

> A terminal coding agent built on the conatus runtime.

## 是什么

基于 [conatus](https://github.com/Fi2zz/conatus) 构建的终端编码智能体。
复用 conatus 的 Agent Loop、工具系统、意图路由、技能沉淀，
专注 coding 场景。

## 特性

- 🖥️ 终端交互（基于 conatus_tui）
- 🔍 文件读写与搜索（read_file / write_file / edit_file / rg / glob）
- ⚡ 意图路由（高频命令零模型调用）
- 🧠 技能沉淀（重复轨迹自动抽象为可复用工具）
- 🤝 多智能体协作（任务板 + 成员运行时）
- 🔒 审批与沙箱（高危操作走审批）

## 快速开始

```bash
# 从源码运行
git clone https://github.com/Fi2zz/conatus_code.git
cd conatus_code
dart pub get
dart run bin/conatus_code.dart
```

## 开发

默认（独立使用）：`pubspec.yaml` 用 git 依赖引 conatus 仓库，clone 后直接
`dart pub get` 即可。

在 [conatus](https://github.com/Fi2zz/conatus) 仓库内开发时，本仓库作为 submodule
挂在 `packages/conatus_code`。该仓库的 `tool/setup_code_filter.sh` 会装一个 git
clean/smudge filter，让 `pubspec.yaml` 里的 `resolution: workspace`：

- 在工作区保持生效 —— 本包成为 conatus pub workspace 的成员，依赖解析到本地
  `packages/*`，改框架对这里立即生效，不必先推送；
- 在 `git add` 时自动注释掉 —— 推送出去的内容不带 `resolution`，独立 clone 因此
  照常走 git 依赖。

未装 filter 的 clone（例如直接 clone 本仓库）拿到的就是注释态，行为与上面「独立使用」
一致。

## 依赖

- [conatus](https://github.com/Fi2zz/conatus) — 框架
- Dart 3.6+；在 conatus 仓库内开发时需 3.11+（workspace 的 glob 语法要求）

## 与 conatus 的关系

conatus_code 是 conatus 的**上层应用**，不是框架的一部分。
coding 相关的能力（文件工具、代码执行）在 conatus 的
[conatus_fs_tools](https://github.com/Fi2zz/conatus/tree/master/packages/conatus_fs_tools)
和 conatus_coding 包里，conatus_code 负责装配它们并暴露终端界面。

## 许可证

MIT
