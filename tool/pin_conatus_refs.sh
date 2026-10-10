#!/usr/bin/env bash
# 把 pubspec.yaml 里所有 conatus 仓库 git 依赖的 ref 钉到指定 commit。
#
# 为什么钉版：本包以 git 源独立分发，16+ 条依赖若浮动跟随 master，
# 外部用户 pub get 拿到的组合与本包 CI 验证过的组合无对应关系
# （父仓在 CI 之后前进即漂移）。钉到具体 SHA 后，「CI 绿」与
# 「用户拿到」是同一棵树。
#
# 用法：
#   bash tool/pin_conatus_refs.sh            # 钉到 conatus origin/master 最新
#   bash tool/pin_conatus_refs.sh <sha>      # 钉到指定 commit
#
# 父仓每次更新后（gitlink 同步前）跑一次并提交本包 pubspec.yaml，
# 让本包 CI 立刻验证新组合。
set -euo pipefail

cd "$(dirname "$0")/.."

REF="${1:-$(git ls-remote https://github.com/Fi2zz/conatus.git master | cut -f1)}"
if [[ ! "$REF" =~ ^[0-9a-f]{40}$ ]]; then
  echo "非法 commit SHA: $REF" >&2
  exit 1
fi

# 只改指向 conatus 仓库的 git 依赖行；其它 hosted 依赖不碰。
# ref 域在逗号或 } 处截止——绝不能越过 path: 字段（`[^}]+` 会连 path 一起
# 吃掉，导致全部依赖 path 丢失）。
PAT='github\.com/Fi2zz/conatus\.git, ref: [^,}]+'
REPL="github.com/Fi2zz/conatus.git, ref: ${REF}"
sed -i '' -E "s|${PAT}|${REPL}|g" pubspec.yaml

echo "已钉到 conatus@${REF}："
grep -n "conatus\.git, ref:" pubspec.yaml | head -3
echo "…（共 $(grep -c 'conatus\.git, ref:' pubspec.yaml) 条）"
if grep -q "conatus\.git, ref: master" pubspec.yaml; then
  echo "错误：仍有残留 ref: master" >&2
  exit 1
fi

# 元检查：ref 替换绝不允许吞掉 path 域（曾发生过 37 条 path 全丢的事故）。
PATHS=$(grep -c "path: packages/" pubspec.yaml)
if [ "$PATHS" -lt 36 ]; then
  echo "错误：path: packages/ 仅剩 $PATHS 处（应 ≥36），ref 替换吞掉了 path" >&2
  git checkout -- pubspec.yaml
  echo "已回滚 pubspec.yaml" >&2
  exit 1
fi
