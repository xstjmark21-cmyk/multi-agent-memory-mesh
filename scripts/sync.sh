#!/bin/bash
# Multi-Agent Memory Mesh — 记忆同步脚本（脱敏参考版）
#
# 作用：把本机 agent 的记忆文件推送到云端 Memory Hub 里"自己那一档"
# 用法：sync.sh "<本地源文件>:<Hub 中的档名>" ["<源2>:<档名2>" ...]
# 示例：sync.sh "$HOME/.agent/memories/MEMORY.md:agent-a_MEMORY.md"
#
# 设计要点：
#   1. 只写自己那一档 → 不会覆盖其他 agent 的记忆
#   2. 用专用 deploy key → 不使用主 SSH 密钥
#   3. 每次全新 clone 到临时目录 → 避免陈旧工作区导致的冲突
#   4. 提交信息带主机名+时间 → Git 历史即审计日志

set -e

# ── 配置（按需修改）──────────────────────────────────────────
REPO="${MEMORY_HUB_REPO:-user@hub-host:/path/to/shared-memory.git}"  # Hub 裸库地址（Tailscale 内网）
WORK="${MEMORY_HUB_WORK:-$HOME/.cache/memory-hub-work}"              # 临时工作目录
KEY="${MEMORY_HUB_KEY:-$HOME/shared-memory/.deploy/deploy_key}"      # 同步专用私钥
BRANCH="${MEMORY_HUB_BRANCH:-master}"
# ────────────────────────────────────────────────────────────

if [ $# -eq 0 ]; then
  echo "用法: $0 \"<源文件>:<目标档名>\" [...]" >&2
  exit 1
fi

GIT_SSH="ssh -o StrictHostKeyChecking=accept-new -i $KEY"

rm -rf "$WORK"
GIT_SSH_COMMAND="$GIT_SSH" git clone -q "$REPO" "$WORK"
cd "$WORK"
mkdir -p memories

echo "=== 同步共享记忆 @ $(date '+%F %T') ==="
for pair in "$@"; do
  src="${pair%%:*}"
  dst="${pair#*:}"
  if [ -f "$src" ]; then
    cp "$src" "memories/$dst"
    echo "  已更新 $dst ($(wc -c <"$src") 字节)"
  else
    echo "  (跳过，源文件不存在: $src)"
  fi
done

git add -A
if git commit -q -m "sync $(hostname) $(date '+%F %T')" 2>/dev/null; then
  GIT_SSH_COMMAND="$GIT_SSH" git push -q origin "$BRANCH" && echo "✅ 已推送 Memory Hub"
else
  echo "(无改动，跳过推送)"
fi

echo "--- Hub 中现有记忆档 ---"
git ls-files memories/
