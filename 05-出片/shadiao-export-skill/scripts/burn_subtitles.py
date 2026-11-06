#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用更好的字幕样式重烧字幕（ASS + libass）

为什么：
  app 自带字幕是「白字 + 黑底方块」，能用但不够精致。
  本脚本读 配音表.json，生成带：
    - 半透明圆角感底框（BorderStyle=3）
    - 关键词黄色高亮
    - 淡入 + 轻微弹入
  的 ASS 字幕，再烧进视频。

用法：
  python3 burn_subtitles.py \
    --video 05-成片/第01集-无字幕.mp4 \
    --manifest 02-配音/第01集/配音表.json \
    --out 05-成片/第01集-字幕.mp4

注意：导出时把 app 的字幕关掉（showSubtitles: false），否则会叠两层。
"""

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

KEYWORDS = [
    "摸鱼", "老板", "KPI", "灵魂", "翻倍", "核心岗位", "斗地主",
    "周报", "升职", "背锅", "工位", "沉默", "测试", "责任",
]

ASS_HEADER = """[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,PingFang SC,54,&H00FFFFFF,&H00FFFFFF,&H00000000,&H78000000,-1,0,0,0,100,100,1,0,3,14,0,2,54,54,200,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""


def ts(seconds: float) -> str:
    seconds = max(0.0, seconds)
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = seconds % 60
    return f"{h}:{m:02d}:{s:05.2f}"


def escape(text: str) -> str:
    return text.replace("\\", "＼").replace("{", "｛").replace("}", "｝")


def highlight(text: str) -> str:
    out = escape(text)
    for kw in sorted(KEYWORDS, key=len, reverse=True):
        if kw in out:
            out = out.replace(kw, r"{\c&H0000D7FF&}" + kw + r"{\c&H00FFFFFF&}")
    return out


def build_ass(manifest: dict) -> str:
    lines = [ASS_HEADER]
    cursor = 0.0
    for line in manifest.get("lines", []):
        dur = float(line.get("duration", 0)) / 1000.0
        text = (line.get("text") or "").strip()
        if text:
            start, end = cursor, cursor + dur
            body = (
                r"{\fad(50,80)\fscx92\fscy92\t(0,120,\fscx100\fscy100)}"
                + highlight(text)
            )
            lines.append(f"Dialogue: 0,{ts(start)},{ts(end)},Default,,0,0,0,,{body}")
        cursor += dur
    return "\n".join(lines) + "\n"


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"命令失败：{' '.join(cmd)}\n{r.stderr}")


def main():
    ap = argparse.ArgumentParser(description="重烧字幕")
    ap.add_argument("--video", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--crf", default="20")
    ap.add_argument("--ratio", default="9:16")
    ap.add_argument("--font", default="PingFang SC")
    args = ap.parse_args()

    manifest = json.loads(Path(args.manifest).read_text(encoding="utf-8-sig"))
    ass = build_ass(manifest)
    tmp = Path(tempfile.mkdtemp(prefix="shadiao_sub_"))
    ass_path = tmp / "sub.ass"
    ass_path.write_text(ass, encoding="utf-8")

    if args.ratio == "9:16":
        w, h = 1080, 1920
    elif args.ratio == "16:9":
        w, h = 1920, 1080
    else:
        w, h = 1080, 1920

    style = args.font.replace("'", r"\'")
    vf = (
        f"scale={w}:{h}:force_original_aspect_ratio=decrease,"
        f"pad={w}:{h}:(ow-iw)/2:(oh-ih)/2:color=black,"
        f"vignette=PI/7,eq=contrast=1.02:saturation=1.04,"
        f"ass={ass_path}:fontsdir=/System/Library/Fonts"
    )

    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    run([
        "ffmpeg", "-y", "-i", str(args.video),
        "-vf", vf,
        "-c:v", "libx264", "-preset", "slow", "-crf", args.crf, "-pix_fmt", "yuv420p",
        "-c:a", "copy", "-movflags", "+faststart",
        str(args.out),
    ])
    print(f">> 字幕已烧录：{args.out}")


if __name__ == "__main__":
    main()
