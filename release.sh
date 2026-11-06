#!/usr/bin/env bash
# 发布到 ClawHub（OpenClaw 技能市场）。
#
# 用法：
#   bash release.sh                       # 用 SKILL.md 里的版本号
#   bash release.sh --dry-run             # 只做检查，不上传
#   bash release.sh --version 1.0.1       # 指定版本
#   bash release.sh --changelog "修了嘴位" # 自定义更新说明
#
# 前置：
#   npm i -g clawhub && clawhub login
#
# 本地目录叫「26-沙雕漫剧」，和 slug 不一致；脚本会临时打一个
# shadiao-manju/ 目录再发布，发完自动清理。
set -euo pipefail

cd "$(dirname "$0")"

SLUG="${SLUG:-shadiao-manju}"
NAME="${NAME:-沙雕漫剧}"
TAGS="${TAGS:-latest}"
DRY_RUN=0
VERSION=""
CHANGELOG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="${2:?}"; shift 2 ;;
    --changelog) CHANGELOG="${2:?}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

[ -f SKILL.md ] || { echo "✗ 当前目录没有 SKILL.md" >&2; exit 1; }
command -v clawhub >/dev/null 2>&1 || { echo "✗ 没装 clawhub：npm i -g clawhub" >&2; exit 1; }

if [ -z "$VERSION" ]; then
  VERSION="$(awk '/^version:[[:space:]]*/{print $2; exit}' SKILL.md | tr -d '"'"'")"
fi
[ -n "$VERSION" ] || { echo "✗ 读不到版本号，用 --version 指定" >&2; exit 1; }

if [ -z "$CHANGELOG" ]; then
  CHANGELOG="沙雕漫剧 v${VERSION}：一句话 / 小说 / 热点 → 1–2 分钟竖屏沙雕动画。剧本、配音、素材、.anime 工程、ffmpeg 收尾全流程脚本化，人工只剩预览和导出两步。"
fi

# ── 1. 环境检查 ───────────────────────────────────────────
echo "── 检查环境 ──"
if ! clawhub whoami >/dev/null 2>&1; then
  echo "✗ 未登录 ClawHub，先跑：clawhub login" >&2
  exit 1
fi
echo "✓ clawhub $(clawhub whoami 2>&1 | tail -1)"

# ── 2. 打临时发布目录 ─────────────────────────────────────
STAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/shadiao-release.XXXXXX")"
STAGE="$STAGE_ROOT/$SLUG"
mkdir -p "$STAGE"
trap 'rm -rf "$STAGE_ROOT"' EXIT

if git rev-parse --git-dir >/dev/null 2>&1 && git rev-parse HEAD >/dev/null 2>&1; then
  # 只打包已提交的文件：.env、成片、缓存天然不在里面
  git ls-files -z | rsync -a --files-from=- --from0 . "$STAGE/"
  echo "✓ 打包来源：git 已跟踪文件"
else
  # 还没提交时，按目录打包并手工排除
  rsync -a \
    --exclude='.git/' --exclude='.env' --exclude='.clawhub/' \
    --exclude='__pycache__/' --exclude='*.pyc' --exclude='.DS_Store' \
    --exclude='*.mp4' --exclude='*.mp3' --exclude='_旧表情/' --exclude='_熊猫版/' \
    --exclude='*_cache/' \
    ./ "$STAGE/"
  echo "✓ 打包来源：工作目录（未提交）"
fi

[ -f "$STAGE/SKILL.md" ] || { echo "✗ 打包后没有 SKILL.md" >&2; exit 1; }

# ── 3. 体积检查（ClawHub 总包上限 50MB）───────────────────
python3 - "$STAGE" <<'PY'
import os, sys
root0 = sys.argv[1]
total = count = 0
big = []
for root, dirs, files in os.walk(root0):
    dirs[:] = [d for d in dirs if d not in {".git", "__pycache__", ".clawhub"}]
    for f in files:
        if f == ".DS_Store":
            continue
        p = os.path.join(root, f)
        try:
            s = os.path.getsize(p)
        except OSError:
            continue
        total += s
        count += 1
        if s > 20 * 1024 * 1024:
            big.append((p, s))
print(f"  文件 {count} 个，合计 {total/1024/1024:.1f}MB")
if total > 50 * 1024 * 1024:
    print("✗ 超过 ClawHub 50MB 上限，先精简。", file=sys.stderr)
    sys.exit(1)
if big:
    print("✗ 单个文件超过 20MB：", file=sys.stderr)
    for p, s in big:
        print(f"  {s/1024/1024:.1f}MB  {p}", file=sys.stderr)
    sys.exit(1)
PY

# ── 4. 发布 ───────────────────────────────────────────────
CMD=(clawhub skill publish "$STAGE" --slug "$SLUG" --name "$NAME" --version "$VERSION" --tags "$TAGS" --changelog "$CHANGELOG")

echo
echo "── 准备发布 ──"
echo "  slug:      $SLUG"
echo "  name:      $NAME"
echo "  version:   $VERSION"
echo "  tags:      $TAGS"

if [ "$DRY_RUN" = "1" ]; then
  echo
  echo "dry-run，未上传。打包目录：$STAGE"
  echo "实际命令："
  echo "  clawhub skill publish \"$STAGE\" --slug \"$SLUG\" --name \"$NAME\" --version \"$VERSION\" --tags \"$TAGS\" --changelog \"$CHANGELOG\""
  exit 0
fi

"${CMD[@]}"

echo
echo "✓ 已发布：https://clawhub.ai/${SLUG}"
echo "  安装：clawhub install ${SLUG}"
echo "  扫描：clawhub scan --slug ${SLUG} --version ${VERSION}"
