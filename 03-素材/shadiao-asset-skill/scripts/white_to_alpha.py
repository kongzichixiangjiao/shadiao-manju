#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""白底转透明（沙雕素材用）

用法：
  python3 white_to_alpha.py body.png
  python3 white_to_alpha.py body.png --trim
  python3 white_to_alpha.py 角色/阿强/*.png --threshold 240 --trim

原理：从图片四边向内 flood fill，把接近纯白的连通区域设为透明。
只吃「纯白背景」的图；复杂背景 / 渐变背景不适用。
"""

import argparse
import sys
from collections import deque
from pathlib import Path

import numpy as np
from scipy.ndimage import binary_closing, binary_fill_holes

try:
    from PIL import Image
except ImportError:
    sys.exit("缺少 Pillow：pip install Pillow")


def is_white(px, threshold):
    r, g, b, a = px
    return a > 0 and r >= threshold and g >= threshold and b >= threshold


def flood_white(img, threshold):
    w, h = img.size
    px = img.load()
    visited = bytearray(w * h)
    q = deque()

    def push(x, y):
        idx = y * w + x
        if not visited[idx] and is_white(px[x, y], threshold):
            visited[idx] = 1
            q.append((x, y))

    for x in range(w):
        push(x, 0)
        push(x, h - 1)
    for y in range(h):
        push(0, y)
        push(w - 1, y)

    while q:
        x, y = q.popleft()
        r, g, b, _ = px[x, y]
        px[x, y] = (r, g, b, 0)
        if x > 0:
            push(x - 1, y)
        if x < w - 1:
            push(x + 1, y)
        if y > 0:
            push(x, y - 1)
        if y < h - 1:
            push(x, y + 1)


def soften_edge(img, threshold):
    """把靠近透明的浅色像素做一点羽化，减少白边。"""
    w, h = img.size
    px = img.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            near_white = min(r, g, b)
            if near_white >= threshold - 12:
                alpha = int(max(0, 255 * (threshold - near_white) / max(1, 255 - threshold)))
                px[x, y] = (r, g, b, min(a, alpha))


def trim(img):
    bbox = img.getbbox()
    return img.crop(bbox) if bbox else img


def fill_enclosed_white(img, threshold):
    """把被轮廓包住的白色区域补回不透明（白衣服/白脸/白鞋）。

    v0.7：必须把「已经透明」的像素排除在 foreground 之外。
    很多 PNG 在 alpha=0 处仍保留 RGB=255，如果只看颜色，透明背景会被当成
    前景，白脸就和画布外连通了，binary_fill_holes 补不上 → 预合成出半透明的头。
    """
    arr0 = np.array(img.convert("RGBA"))
    alpha0 = arr0[..., 3]
    rgb = arr0[..., :3].astype(np.int16)
    near_white = np.all(rgb >= threshold - 8, axis=2)
    foreground = (alpha0 > 10) & ~near_white
    closed = binary_closing(foreground, structure=np.ones((9, 9)))
    filled = binary_fill_holes(closed)
    holes = filled & ~foreground

    arr = arr0
    arr[..., 3] = np.where(holes, 255, arr[..., 3])
    print(f"  · 补回白色区域 {int(holes.sum())} px")
    return Image.fromarray(arr, "RGBA")


def process(path, threshold, do_trim, do_soften, fill_holes=False):
    img = Image.open(path).convert("RGBA")
    flood_white(img, threshold)
    if fill_holes:
        img = fill_enclosed_white(img, threshold)
    if do_soften and not fill_holes:
        soften_edge(img, threshold)
    if do_trim:
        img = trim(img)
    img.save(path, "PNG", optimize=True)
    return img.size


def main():
    ap = argparse.ArgumentParser(description="白底转透明")
    ap.add_argument("paths", nargs="+", help="PNG/JPG 路径，支持通配符（由 shell 展开）")
    ap.add_argument("--threshold", type=int, default=245, help="白色阈值，默认 245")
    ap.add_argument("--trim", action="store_true", help="裁掉透明边")
    ap.add_argument("--no-soften", action="store_true", help="不做边缘羽化")
    ap.add_argument("--fill-holes", action="store_true", help="补回被轮廓包住的白色区域（白衣服/白脸必开）")
    args = ap.parse_args()

    for p in args.paths:
        path = Path(p)
        if not path.is_file():
            print(f"  ! 跳过（不存在）：{path}", file=sys.stderr)
            continue
        try:
            size = process(path, args.threshold, args.trim, not args.no_soften, args.fill_holes)
            print(f"  ✓ {path} → {size[0]}×{size[1]}")
        except Exception as e:
            print(f"  ✗ {path}：{e}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
