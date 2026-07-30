#!/usr/bin/env python3
"""生成 ValCompass 应用图标：五档色阶构成的估值刻度盘 + 指针。
色值与应用内 Theme.zone(_:) 的深色变体一致，图标与界面同源。"""
import math

W = 1024
CX = 512.0
R = 350.0          # 弧线半径（中线）
STROKE = 92.0      # 弧线粗细
CY = 686.0         # 轴心：使「弧顶到弧底」这段视觉主体在画布中居中
GAP_DEG = 2.2      # 档位之间的留白（角度）
SCORE = 72.0       # 指针指向（落在「偏高」档）

BG = "#1C1A16"
ZONES = ["#82ADC8", "#9CBBCE", "#ABA598", "#CFA55F", "#CB8869"]
INK = "#F4F0E8"


def pt(angle_deg, radius):
    a = math.radians(angle_deg)
    return CX + radius * math.cos(a), CY + radius * math.sin(a)


def arc_path(a0, a1, radius):
    x0, y0 = pt(a0, radius)
    x1, y1 = pt(a1, radius)
    large = 1 if (a1 - a0) > 180 else 0
    return f"M {x0:.2f} {y0:.2f} A {radius:.2f} {radius:.2f} 0 {large} 1 {x1:.2f} {y1:.2f}"


parts = [
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{W}" viewBox="0 0 {W} {W}">',
    f'<rect width="{W}" height="{W}" fill="{BG}"/>',
]

# 五档弧线：180°→360° 为上半圆，从左到右依次对应 0–100
for i, color in enumerate(ZONES):
    a0 = 180 + i * 36 + (GAP_DEG / 2 if i > 0 else 0)
    a1 = 180 + (i + 1) * 36 - (GAP_DEG / 2 if i < 4 else 0)
    parts.append(
        f'<path d="{arc_path(a0, a1, R)}" fill="none" stroke="{color}" '
        f'stroke-width="{STROKE}" stroke-linecap="butt"/>'
    )

# 指针：自轴心指向当前分数。不画尾端，避免轴心下方多出一个凸起
angle = 180 + SCORE / 100 * 180
tip = pt(angle, R - STROKE / 2 - 30)
parts.append(
    f'<line x1="{CX:.2f}" y1="{CY:.2f}" x2="{tip[0]:.2f}" y2="{tip[1]:.2f}" '
    f'stroke="{INK}" stroke-width="27" stroke-linecap="round"/>'
)
# 轴心
parts.append(f'<circle cx="{CX}" cy="{CY}" r="53" fill="{INK}"/>')
parts.append(f'<circle cx="{CX}" cy="{CY}" r="21" fill="{BG}"/>')

parts.append("</svg>")
print("\n".join(parts))

# 用法（需要 rsvg-convert：brew install librsvg）：
#   python3 Tools/make_app_icon.py > /tmp/icon.svg
#   rsvg-convert -w 1024 -h 1024 /tmp/icon.svg \
#     -o ValCompass/Assets.xcassets/AppIcon.appiconset/icon-1024.png
