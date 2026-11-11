"""多设备布局配置对照示意（离屏拼图，不启动模拟器）。

直接正则读取 Features/Home/DeviceLayoutConfig.swift 的七档配置，
用真实背景素材 + 真实 icon_folder 贴图画「三区比例 / 收藏夹行数 / 图标尺寸」。
底部另画三种三区比例样例，方便不编译就判断数值方向。

用法：python3 design/background-v4/preview_device_layout.py [输出路径]
输出默认 /tmp/device_layout_preview.png
"""
from PIL import Image, ImageDraw, ImageFont
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONFIG = os.path.join(
    ROOT,
    "source/appSuperPhotos/SuperPhotos/Features/Home/DeviceLayoutConfig.swift",
)
BG_DIR = os.path.join(ROOT, "design/background-v4")
ICON_DIR = os.path.join(ROOT, "design/icons")
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/device_layout_preview.png"

FONT_PATH = "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"

TEXT = (36, 42, 52)
MUTED = (108, 116, 130)
BLUE = (52, 118, 210)
ORANGE = (218, 138, 52)
GREEN = (58, 148, 108)
LINE = (222, 226, 233)
CARD = (255, 255, 255)

DEFAULT_LIGHT = "scenery_background_light"
DEFAULT_DARK = "scenery_background_dark"


def font(size, bold=False):
    try:
        f = ImageFont.truetype(FONT_PATH, size, index=0)
        # Arial Unicode 无粗体字重，用描边模拟
        return f
    except Exception:
        return ImageFont.load_default()


def bold_text(d, xy, text, size, fill, anchor=None):
    d.text(xy, text, font=font(size, True), fill=fill, anchor=anchor,
           stroke_width=1 if size >= 20 else 0,
           stroke_fill=fill)


def grab(pattern, body, key, default):
    m = re.search(pattern % key, body)
    return float(m.group(1)) if m else default


def read_config():
    text = open(CONFIG, encoding="utf-8").read()
    labels = dict(re.findall(r'case\s+(\w+)\s*=\s*"([^"]+)"', text))

    favorites = {}
    for m in re.finditer(r"static let (\w+)\s*=\s*FavoriteSettings\((.*?)\)", text, re.S):
        b = m.group(2)
        pat = r"%s\s*:\s*(-?[0-9.]+)"
        favorites[m.group(1)] = dict(
            rows=int(grab(pat, b, "rows", 5)),
            icon=grab(pat, b, "iconSize", 58),
            title=grab(pat, b, "titleSize", 11),
            badge=grab(pat, b, "badgeSize", 9),
        )

    zones = {}
    for m in re.finditer(r"static let (\w+)\s*=\s*ZoneRatios\((.*?)\)", text, re.S):
        b = m.group(2)
        pat = r"%s\s*:\s*(-?[0-9.]+)"
        zones[m.group(1)] = (
            grab(pat, b, "top", 0),
            grab(pat, b, "middle", 1),
            grab(pat, b, "bottom", 0),
        )

    backgrounds = {}
    for m in re.finditer(r"static let (\w+)\s*=\s*SceneryAssets\((.*?)\)", text, re.S):
        b = m.group(2)
        light = re.search(r'light:\s*"([^"]+)"', b)
        dark = re.search(r'dark:\s*"([^"]+)"', b)
        backgrounds[m.group(1)] = (
            light.group(1) if light else DEFAULT_LIGHT,
            dark.group(1) if dark else DEFAULT_DARK,
        )
    for m in re.finditer(r"static let (\w+)\s*=\s*SceneryAssets\.standard", text):
        backgrounds[m.group(1)] = (DEFAULT_LIGHT, DEFAULT_DARK)

    entries = []
    for m in re.finditer(
        r"static let (\w+)\s*=\s*DeviceLayoutEntry\((.*?)\n\s*\)", text, re.S
    ):
        b = m.group(2)
        form = re.search(r"form:\s*\.(\w+)", b)
        bg_ref = re.search(r"background:\s*(\w+)", b)
        fav_ref = re.search(r"favorites:\s*(\w+)", b)
        zone_ref = re.search(r"zones:\s*(\w+)", b)
        if not (form and bg_ref and fav_ref and zone_ref):
            continue
        entries.append(dict(
            key=form.group(1),
            label=labels.get(form.group(1), form.group(1)),
            background=backgrounds.get(bg_ref.group(1), (DEFAULT_LIGHT, DEFAULT_DARK)),
            favorites=favorites.get(fav_ref.group(1), favorites.get("compactFavorites", dict(
                rows=5, icon=58, title=11, badge=9))),
            zones=zones.get(zone_ref.group(1), (0, 1, 0)),
        ))
    return entries


# 仅用于示意：真机尺寸由运行时窗口决定，不参与任何计算。
DEVICE_SIZES = {
    "iPhonePortrait": (393, 852),
    "iPhoneLandscape": (852, 393),
    "iPadPortrait": (820, 1180),
    "iPadLandscape": (1180, 820),
    "duoOuterScreen": (393, 852),
    "duoInnerPortrait": (768, 1024),
    "duoInnerLandscape": (1024, 768),
}

BG_CACHE = {}


def background_crop(name, w, h):
    """aspectFill + 顶对齐（origin.y = 0），与 SceneryLayout.metrics 一致。"""
    key = (name, w, h)
    if key in BG_CACHE:
        return BG_CACHE[key]
    path = os.path.join(BG_DIR, name + ".png")
    if not os.path.exists(path):
        path = os.path.join(BG_DIR, DEFAULT_LIGHT + ".png")
    img = Image.open(path).convert("RGB")
    iw, ih = img.size
    scale = max(w / iw, h / ih)
    sw, sh = int(round(iw * scale)), int(round(ih * scale))
    img = img.resize((sw, sh), Image.LANCZOS)
    left = max(0, (sw - w) // 2)
    out = img.crop((left, 0, left + w, min(h, sh)))
    if out.height < h:
        base = Image.new("RGB", (w, h), (238, 235, 228))
        base.paste(out, (0, 0))
        out = base
    BG_CACHE[key] = out
    return out


FOLDER = Image.open(os.path.join(ICON_DIR, "icon_folder.png")).convert("RGBA")
FOLDER_SELECTED = Image.open(
    os.path.join(ICON_DIR, "icon_folder_selected.png")
).convert("RGBA")


def draw_screen(entry):
    """返回一张 mini 屏幕：真实背景 + 三区色带 + 收藏夹列图标。"""
    dw, dh = DEVICE_SIZES.get(entry["key"], (393, 852))
    if dw > dh:
        w = 250
        h = max(90, int(round(250 * dh / dw)))
    else:
        h = 214
        w = max(90, int(round(214 * dw / dh)))
    canvas = background_crop(entry["background"][0], w, h).convert("RGBA")
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    o = ImageDraw.Draw(overlay)

    top, mid, bottom = entry["zones"]
    total = max(0.0001, top + mid + bottom)
    y0 = 0
    y1 = h * top / total
    y2 = y1 + h * mid / total
    y3 = float(h)
    bands = [(y0, y1, (218, 138, 52), "上"),
             (y1, y2, (52, 118, 210), "中"),
             (y2, y3, (58, 148, 108), "下")]
    for a, b, color, name in bands:
        if b - a < 0.6:
            continue
        o.rectangle((0, a, w, b), fill=color + (46,))
        o.rectangle((0, a, w - 1, b), outline=color + (200,), width=2)
        if b - a >= 22:
            o.text((6, (a + b) / 2), name, font=font(13, True),
                   fill=color, anchor="lm", stroke_width=1, stroke_fill=color)

    canvas = Image.alpha_composite(canvas, overlay)
    d = ImageDraw.Draw(canvas)

    # 收藏夹列：按配置行数与图标尺寸，画在中区右侧（示意，不还原滚轮淡出）。
    fav = entry["favorites"]
    rows = max(1, fav["rows"])
    pt = w / dw
    icon = max(9, min(fav["icon"] * pt, (y2 - y1) / rows * 0.72, w * 0.30))
    cx = w - max(12, icon * 0.62)
    band_h = max(1, y2 - y1)
    for i in range(rows):
        cy = y1 + band_h * (i + 0.5) / rows
        src = FOLDER_SELECTED if i == rows // 2 else FOLDER
        tile = src.resize((int(icon), int(icon)), Image.LANCZOS)
        canvas.paste(tile, (int(cx - icon / 2), int(cy - icon / 2)), tile)
    d.rectangle((0, 0, w - 1, h - 1), outline=(90, 96, 108), width=1)
    return canvas, (dw, dh), (w, h)


def fmt(v):
    return ("%g" % v)


def main():
    entries = read_config()
    if not entries:
        raise SystemExit("未从 DeviceLayoutConfig.swift 解析到任何形态配置")

    CARD_W, CARD_H = 740, 292
    PAD, COLS = 26, 2
    rows_n = (len(entries) + COLS - 1) // COLS
    W = PAD * 2 + COLS * CARD_W + (COLS - 1) * 18
    H = 132 + rows_n * (CARD_H + 18) + 300

    canvas = Image.new("RGB", (W, H), (245, 246, 249))
    d = ImageDraw.Draw(canvas)
    bold_text(d, (PAD, 28), "多设备布局配置 · 七形态一览", 36, TEXT)
    d.text((PAD, 76),
           "读取 DeviceLayoutConfig.swift 当前数值 · 真实背景素材与 icon_folder 贴图 · 离屏拼图（非真机截图）",
           font=font(17), fill=MUTED)
    d.text((PAD, 102),
           "色带：橙=上区留白 / 蓝=中间三栏行 / 绿=下区道具带；右侧图标数量与大小取当前收藏夹配置",
           font=font(16), fill=MUTED)

    for idx, entry in enumerate(entries):
        col, row = idx % COLS, idx // COLS
        x = PAD + col * (CARD_W + 18)
        y = 132 + row * (CARD_H + 18)
        d.rounded_rectangle((x, y, x + CARD_W, y + CARD_H), radius=14,
                            fill=CARD, outline=LINE, width=1)
        bold_text(d, (x + 20, y + 14), entry["label"], 23, TEXT)

        screen, dev, mini = draw_screen(entry)
        sx, sy = x + 22, y + 52
        canvas.paste(screen.convert("RGB"), (sx, sy))
        d = ImageDraw.Draw(canvas)
        d.text((sx, sy + mini[1] + 6),
               "示意 %d × %d pt" % dev, font=font(14), fill=MUTED)

        tx = sx + 274
        ty = y + 54
        top, mid, bottom = entry["zones"]
        total = max(0.0001, top + mid + bottom)
        lines = [
            ("背景浅", entry["background"][0]),
            ("背景深", entry["background"][1]),
            ("收藏夹", "%d 行 · 图标 %spt · 标题 %spt · 徽章 %spt" % (
                entry["favorites"]["rows"], fmt(entry["favorites"]["icon"]),
                fmt(entry["favorites"]["title"]), fmt(entry["favorites"]["badge"]))),
            ("三区权重", "%s : %s : %s" % (fmt(top), fmt(mid), fmt(bottom))),
            ("三区占比", "上 %.0f%% / 中 %.0f%% / 下 %.0f%%" % (
                top / total * 100, mid / total * 100, bottom / total * 100)),
            ("中间区高", "≈ %.0fpt（示意容器 %dpt）" % (
                dev[1] * mid / total - 150, dev[1] - 150)),
        ]
        for label, value in lines:
            d.rounded_rectangle((tx, ty, tx + 76, ty + 27), radius=7, fill=(235, 240, 248))
            d.text((tx + 38, ty + 13), label, font=font(14), fill=(70, 92, 130), anchor="mm")
            d.text((tx + 88, ty + 4), value, font=font(15), fill=TEXT)
            ty += 36

    # 底部：三区比例样例
    by = 132 + rows_n * (CARD_H + 18) + 8
    d.rounded_rectangle((PAD, by, W - PAD, by + 262), radius=14,
                        fill=CARD, outline=LINE, width=1)
    bold_text(d, (PAD + 22, by + 16), "三区比例怎么调（同一 600pt 容器的三种取值）", 24, TEXT)
    d.text((PAD + 22, by + 50),
           "只改 DeviceLayoutConfig.swift 里对应形态的 ZoneRatios(top:middle:bottom)，数值会自动归一化，不要求和为 1",
           font=font(16), fill=MUTED)

    samples = [
        ("默认 0 : 1 : 0", (0, 1, 0), "中间区占满容器，等于旧的 1.44 倍被屏高钳住后的效果"),
        ("1 : 7 : 2", (1, 7, 2), "顶栏下留 10%，道具区留 20%，三栏行收进中间 70%"),
        ("1 : 6 : 3", (1, 6, 3), "下区更大：宽屏想让销毁设备单独占一条带时可用"),
    ]
    sw, sh = 150, 130
    for i, (title, (a, b, c), note) in enumerate(samples):
        bx = PAD + 22 + i * 478
        cy = by + 86
        d.rounded_rectangle((bx, cy, bx + sw, cy + sh), radius=6,
                            fill=(238, 240, 245), outline=LINE, width=1)
        total = max(0.0001, a + b + c)
        acc = 0.0
        for val, color, name in [(a, ORANGE, "上"), (b, BLUE, "中"), (c, GREEN, "下")]:
            hh = sh * val / total
            if hh > 0.5:
                d.rectangle((bx + 1, cy + acc, bx + sw - 1, cy + acc + hh),
                            fill=tuple(int(v * 0.35 + 255 * 0.65) for v in color),
                            outline=color, width=2)
                if hh >= 16:
                    d.text((bx + sw / 2, cy + acc + hh / 2), name,
                           font=font(15, True), fill=color, anchor="mm",
                           stroke_width=1, stroke_fill=color)
            acc += hh
        bold_text(d, (bx + sw + 14, cy + 4), title, 20, TEXT)
        d.text((bx + sw + 14, cy + 34), note, font=font(15), fill=MUTED)

    d.text((PAD + 22, by + 228),
           "手工调整：改 Swift → 重跑本脚本看图 → Run 到真机；DEBUG HUD 的 form 行会显示当前命中的形态。",
           font=font(16), fill=TEXT)
    d.text((PAD + 22, by + 250),
           "背景换图：把新 imageset 名填进 background.light / dark；名字写错会自动回退官方成品图。",
           font=font(15), fill=MUTED)

    canvas.save(OUT)
    print("saved:", OUT, canvas.size)
    for e in entries:
        print("%-18s bg=%s fav=%d行/%gpt zones=%s" % (
            e["label"], e["background"][0], e["favorites"]["rows"],
            e["favorites"]["icon"], e["zones"]))


if __name__ == "__main__":
    main()
