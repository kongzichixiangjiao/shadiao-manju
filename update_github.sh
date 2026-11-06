#!/usr/bin/env bash
# 提交并推送到 GitHub。
#
# 只给仓库维护者用，不属于创作工作流。默认只提交到本地，不会联网。
#
# 用法：
#   bash update_github.sh "改了什么"                       # 只提交到本地
#   bash update_github.sh "改了什么" --yes                  # 提交并推送（需已配 origin）
#   GITHUB_REPO=git@github.com:you/your-repo.git \
#     bash update_github.sh "改了什么" --yes                # 首次：自动 git init 并添加 origin
#
# 推送前会做三道检查：
#   1. .env / .env.* 不许进版本库（.env.example 除外）
#   2. 暂存内容里不许出现常见密钥格式
#   3. 单文件超过 50MB 拒收
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

STAMP="$(date '+%Y-%m-%d %H:%M')"
PUSH=0
MSG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --yes) PUSH=1; shift ;;
    -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    -*) echo "未知参数：$1" >&2; exit 2 ;;
    *) MSG="$1"; shift ;;
  esac
done
MSG="${MSG:-update: 常规更新 ($STAMP)}"

command -v git >/dev/null 2>&1 || { echo "✗ 缺少 git" >&2; exit 1; }

# ── 0. 初始化 ─────────────────────────────────────────────
if [ ! -d .git ]; then
  git init -b main >/dev/null
  echo "已初始化仓库：$REPO_DIR"
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  if [ -n "${GITHUB_REPO:-}" ]; then
    git remote add origin "$GITHUB_REPO"
    echo "已添加 origin：$GITHUB_REPO"
  elif [ "$PUSH" = "1" ]; then
    echo "✗ 没有 origin，也没给 GITHUB_REPO。先设 GITHUB_REPO=<仓库地址>，或先去 GitHub 建空仓库。" >&2
    exit 1
  else
    echo "提醒：未配置 origin，本次只提交到本地。"
  fi
fi

git add -A

if [ -z "$(git status --porcelain)" ]; then
  echo "没有变更，无需提交。"
  exit 0
fi

# ── 1. 配置/密钥文件闸门 ──────────────────────────────────
LEAKED="$(git diff --cached --name-only | grep -E '(^|/)\.env(\..+)?$' | grep -vE '(^|/)\.env\.example$' || true)"
if [ -n "$LEAKED" ]; then
  echo "✗ 以下配置/密钥文件被加入了暂存区，已中止：" >&2
  echo "$LEAKED" >&2
  echo "先执行：git restore --staged <文件>" >&2
  exit 1
fi

# ── 2. 密钥闸门 ───────────────────────────────────────────
SECRET_RE='sk-[A-Za-z0-9]{16,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN (RSA|OPENSSH|EC) PRIVATE KEY-----'
if git diff --cached | grep -nE "$SECRET_RE" >/dev/null 2>&1; then
  echo "✗ 暂存内容里发现疑似密钥，已中止：" >&2
  git diff --cached | grep -nE "$SECRET_RE" | cut -c1-120 >&2 || true
  echo "确认是误报的话，删掉后重新提交。不要用 --no-verify 绕过。" >&2
  exit 1
fi

# ── 3. 大文件提醒（GitHub 单文件上限 100MB）──────────────
python3 - <<'PY'
import os, subprocess, sys
files = subprocess.check_output(["git", "diff", "--cached", "--name-only"], text=True).splitlines()
big = [(f, os.path.getsize(f)) for f in files if f and os.path.exists(f) and os.path.getsize(f) > 50 * 1024 * 1024]
if big:
    print("✗ 以下文件超过 50MB，不建议提交：", file=sys.stderr)
    for f, s in big:
        print(f"  {s/1024/1024:.1f}MB  {f}", file=sys.stderr)
    print("把它们放进 .gitignore，或者改用 Git LFS。", file=sys.stderr)
    sys.exit(1)
PY

# ── 4. 提交 ───────────────────────────────────────────────
echo "── 本次变更 ──"
git status --short

git commit -m "$MSG"
echo "✓ 已提交：$(git rev-parse --short HEAD)"

# ── 5. 推送（必须显式 --yes）──────────────────────────────
if [ "$PUSH" != "1" ]; then
  echo "未推送。确认无误后加 --yes 再跑一次："
  echo "  bash update_github.sh \"$MSG\" --yes"
  exit 0
fi

git push -u origin HEAD
echo "── 完成：$(git remote get-url origin) ($(git rev-parse --short HEAD)) ──"
