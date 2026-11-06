#!/usr/bin/env bash
# 提交并推送到 GitHub。
#
# 用法：
#   bash update_github.sh "改了什么"
#   GITHUB_REPO=git@github.com:you/your-repo.git bash update_github.sh
#
# 首次运行会自动 git init 并添加 origin。推之前先确认仓库已创建：
#   https://github.com/new?name=shadiao-manju
#
# 提交前会做两道检查：
#   1. .env 不许进版本库
#   2. 暂存内容里不许出现常见密钥格式
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

REMOTE="${GITHUB_REPO:-git@github.com:kongzichixiangjiao/shadiao-manju.git}"
STAMP="$(date '+%Y-%m-%d %H:%M')"
MSG="${1:-update: 常规更新 ($STAMP)}"

command -v git >/dev/null 2>&1 || { echo "✗ 缺少 git" >&2; exit 1; }

# ── 0. 初始化 ─────────────────────────────────────────────
if [ ! -d .git ]; then
  git init -b main >/dev/null
  echo "已初始化仓库：$REPO_DIR"
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  git remote add origin "$REMOTE"
  echo "已添加 origin：$REMOTE"
  if ! git ls-remote --exit-code origin >/dev/null 2>&1; then
    echo "提醒：远程仓库还不可用。先去 https://github.com/new?name=shadiao-manju 建一个空仓库。"
  fi
fi

git add -A

if [ -z "$(git status --porcelain)" ]; then
  echo "没有变更，无需提交。"
  exit 0
fi

# ── 1. .env 闸门 ──────────────────────────────────────────
if git diff --cached --name-only | grep -qE '(^|/)\.env$'; then
  echo "✗ .env 被加入了暂存区，已中止。先执行：git restore --staged .env" >&2
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

# ── 4. 提交 + 推送 ────────────────────────────────────────
echo "── 本次变更 ──"
git status --short

git commit -m "$MSG"
git push -u origin HEAD

echo "── 完成：$(git remote get-url origin) ($(git rev-parse --short HEAD)) ──"
