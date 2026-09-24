#!/usr/bin/env bash
# 把 conatus_code 打包成单个自包含可执行文件（内嵌 Dart runtime）。
#
# 默认产出 <包根>/dist/nava，可用第一个参数覆盖输出路径；脚本不依赖调用时的
# cwd：
#   bash tool/build_binary.sh                # -> <包根>/dist/nava
#   bash tool/build_binary.sh /tmp/nava      # -> /tmp/nava
#
# 产物换机器直接可用（不需要目标机器装 Dart SDK）；但 OS 沙箱后端（launcher）
# 仍在运行时从 pub 缓存定位，清空 pub 缓存后沙箱会 fail-closed，详见 README。
set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:-$package_root/dist/nava}"

mkdir -p "$(dirname "$output")"
version="$(grep '^version:' "$package_root/pubspec.yaml" | awk '{print $2}')"
dart compile exe "$package_root/bin/conatus_code.dart" \
  -DNAVA_VERSION="$version" -o "$output"
chmod +x "$output"

echo "产物：${output}（$(du -h "$output" | awk '{print $1}')）"
