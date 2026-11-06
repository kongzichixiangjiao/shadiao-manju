#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用火山方舟 Seedream 出图（沙雕漫剧素材用）

为什么单独写一个：
  - ai-manju-production 里的 seedream_multi.py 绑死了那套季目录结构；
  - 本 skill 需要「一张图一个命令」，并且要能带参考图、能指定 9:16。

密钥查找顺序：
  $ARK_API_KEY → 仓库根目录 .env → $SHADIAO_ENV 指定的 .env

本仓库不包含任何密钥；.env 已被 .gitignore 忽略。

用法：
  python3 gen_seedream.py --out 背景/会议室.png \
    --prompt "..." --refs 角色/阿强/body.png --size 1024x1536

  --size 失败会自动退回 "2K"，最后统一裁成 1024x1536。
"""

import argparse
import base64
import json
import os
import sys
import time
import urllib.request
from pathlib import Path

from openai import OpenAI

DEFAULT_MODEL = "doubao-seedream-5-0-pro-260628"
ARK_BASE = "https://ark.cn-beijing.volces.com/api/v3"

SKILL_ROOT = Path(__file__).resolve().parents[3]
ENV_PATHS = [
    SKILL_ROOT / ".env",
    Path(
        os.environ.get("SHADIAO_ENV", Path.home() / ".config" / "shadiao" / ".env")
    ).expanduser(),
]


def find_key():
    key = os.environ.get("ARK_API_KEY", "").strip()
    if key:
        return key
    for path in ENV_PATHS:
        if not os.path.isfile(path):
            continue
        for line in open(path, encoding="utf-8"):
            if line.strip().startswith("ARK_API_KEY="):
                v = line.split("=", 1)[1].strip().strip('"').strip("'")
                if v:
                    return v
    return ""


def to_data_url(path):
    with open(path, "rb") as fh:
        return "data:image/png;base64," + base64.b64encode(fh.read()).decode()


def cover_crop(img_path, out_path, w, h):
    from PIL import Image

    im = Image.open(img_path).convert("RGBA")
    sw, sh = im.size
    scale = max(w / sw, h / sh)
    nw, nh = max(w, int(round(sw * scale))), max(h, int(round(sh * scale)))
    im = im.resize((nw, nh), Image.LANCZOS)
    left = (nw - w) // 2
    top = (nh - h) // 2
    im.crop((left, top, left + w, top + h)).save(out_path, "PNG", optimize=True)
    return (w, h)


def main():
    ap = argparse.ArgumentParser(description="Seedream 出图")
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--out", required=True, help="输出路径（png）")
    ap.add_argument("--refs", nargs="*", default=[], help="参考图路径（可多张）")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--size", default="1024x1536")
    ap.add_argument("--fallback-size", default="2K")
    ap.add_argument("--target", default="1024x1536", help="最终裁切尺寸")
    ap.add_argument("--raw", action="store_true", help="保留原图不裁切")
    args = ap.parse_args()

    key = find_key()
    if not key:
        raise SystemExit("缺 ARK_API_KEY（设置环境变量，或复制 .env.example 为 .env 再填）")

    refs = [to_data_url(p) for p in args.refs]
    client = OpenAI(base_url=ARK_BASE, api_key=key, timeout=300)

    extra = {"watermark": False}
    if refs:
        extra["image"] = refs

    t0 = time.time()
    try:
        r = client.images.generate(
            model=args.model,
            prompt=args.prompt,
            size=args.size,
            response_format="url",
            extra_body=extra,
        )
    except Exception as e:  # noqa: BLE001
        print(f"  ! size={args.size} 失败（{str(e)[:120]}），改用 {args.fallback_size}", file=sys.stderr)
        r = client.images.generate(
            model=args.model,
            prompt=args.prompt,
            size=args.fallback_size,
            response_format="url",
            extra_body=extra,
        )

    url = r.data[0].url
    raw = urllib.request.urlopen(url, timeout=300).read()

    out = args.out
    os.makedirs(os.path.dirname(os.path.abspath(out)) or ".", exist_ok=True)
    tmp = out + ".raw"
    with open(tmp, "wb") as fh:
        fh.write(raw)

    if args.raw:
        os.replace(tmp, out)
        size = "raw"
    else:
        w, h = (int(x) for x in args.target.lower().split("x"))
        cover_crop(tmp, out, w, h)
        os.remove(tmp)
        size = f"{w}x{h}"

    print(f"✓ {out}  {size}  {round(time.time() - t0, 1)}s  refs={len(refs)}")


if __name__ == "__main__":
    main()
