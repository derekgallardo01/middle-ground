#!/usr/bin/env python3
"""Generate the site's raster brand assets into site/assets/.

Run once, or whenever the brand changes — the output is committed, so the Docker image needs no
image tooling and a deploy can never fail on asset generation.

    python3 site/make_assets.py

Two sources, for two different reasons:

The **favicon** is drawn here from primitives rather than downscaled from the app icon. Measured:
the mark occupies 39% of the width of AppIcon-1024.png, sitting on near-white #F7F6F3. Scaled to
32px that leaves a ~12px mark on a white field — invisible in a browser tab. A favicon needs the
mark cropped tight to its own bounding box. The geometry below matches brand/logo-mark.svg and
LogoMark.swift exactly.

The **touch icons** do come from the app icon, because there its composition and margins are
already right — iOS just needs the alpha corners flattened onto an opaque background.

Fonts: Inter (SIL Open Font License), vendored under site/assets/fonts/. Deliberately not the
macOS system faces — SF's licence is scoped to Apple-platform UI work, and a marketing card is
not that.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).parent
REPO = HERE.parent
ASSETS = HERE / "assets"
VENDOR = HERE / "vendor"
ICON = REPO / "ios" / "MiddleGround" / "App" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"
BRAND_FAVICON = REPO / "brand" / "favicon.svg"
INTER = VENDOR / "Inter.ttf"

SAND = (247, 246, 243)
SLATE = (51, 65, 85)
WARM_600 = (113, 113, 122)
INDIGO = (99, 102, 241)
TEAL = (20, 184, 166)
CORAL = (255, 143, 163)

# The mark's own bounding box inside the 512 viewBox: the figures' heads start at y=82
# (130-48) and the bodies end at y=470; x runs 95 → 417.
MARK_BOX = (95, 82, 417, 470)

HEART = [
    ((256, 340), (256, 340), (190, 285), (190, 235)),
    ((190, 235), (190, 185), (230, 170), (256, 210)),
    ((256, 210), (282, 170), (322, 185), (322, 235)),
    ((322, 235), (322, 285), (256, 340), (256, 340)),
]


def font(size: int, weight: str = "Regular") -> ImageFont.FreeTypeFont:
    face = ImageFont.truetype(str(INTER), size)
    face.set_variation_by_name(weight)
    return face


def bezier(p0, p1, p2, p3, steps: int = 48):
    """Flatten one cubic segment to points — ImageDraw has no curve primitive."""
    out = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        out.append((
            u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0],
            u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1],
        ))
    return out


def draw_mark(size: int, padding: float = 0.08) -> Image.Image:
    """The two-figures-and-a-heart mark, cropped to itself and padded, at `size` square.

    Drawn at 8× and downsampled: that is supersampled antialiasing, which is what makes the
    16px favicon frame legible rather than a smear.
    """
    scale = 8
    canvas = 512 * scale
    big = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw = ImageDraw.Draw(big)
    s = lambda v: v * scale  # noqa: E731 — viewBox units → supersampled pixels

    draw.ellipse([s(122), s(82), s(218), s(178)], fill=INDIGO)
    draw.rounded_rectangle([s(95), s(190), s(255), s(470)], radius=s(80), fill=INDIGO)
    draw.ellipse([s(294), s(82), s(390), s(178)], fill=TEAL)
    draw.rounded_rectangle([s(257), s(190), s(417), s(470)], radius=s(80), fill=TEAL)

    points: list[tuple[float, float]] = []
    for seg in HEART:
        points.extend((s(x), s(y)) for x, y in bezier(*seg))
    draw.polygon(points, fill=CORAL)

    x0, y0, x1, y1 = (v * scale for v in MARK_BOX)
    mark = big.crop((int(x0), int(y0), int(x1), int(y1)))

    # Square it, so a non-square mark is centred rather than stretched.
    side = max(mark.width, mark.height)
    pad = int(side * padding)
    square = Image.new("RGBA", (side + pad * 2, side + pad * 2), (0, 0, 0, 0))
    square.paste(mark, (pad + (side - mark.width) // 2, pad + (side - mark.height) // 2), mark)
    return square.resize((size, size), Image.LANCZOS)


def opaque(image: Image.Image, size: int, background=SAND) -> Image.Image:
    """Flatten onto an opaque background — iOS composites a transparent touch icon on black."""
    scaled = image.resize((size, size), Image.LANCZOS)
    flat = Image.new("RGB", (size, size), background)
    flat.paste(scaled, (0, 0), scaled)
    return flat


def social_card() -> Image.Image:
    """The Open Graph card, 2400×1256.

    2×(1200×630). iOS 16+ has been unreliable about rendering a full-width preview from the
    classic 1200×630, and a larger image at the same 1.91:1 ratio satisfies every other consumer
    unchanged. Newer iOS also crops toward square, so nothing that matters sits near an edge.
    """
    w, h = 2400, 1256
    card = Image.new("RGB", (w, h), SAND)
    draw = ImageDraw.Draw(card)

    for x in range(w):  # indigo → teal, the app's own gradient
        t = x / (w - 1)
        draw.line(
            [(x, 0), (x, 14)],
            fill=tuple(int(INDIGO[i] + (TEAL[i] - INDIGO[i]) * t) for i in range(3)),
        )

    def centred(text: str, y: int, face: ImageFont.FreeTypeFont, fill) -> None:
        left, top, right, bottom = draw.textbbox((0, 0), text, font=face)
        draw.text(((w - (right - left)) / 2 - left, y - top), text, font=face, fill=fill)

    # Stacked and centred rather than a left-aligned lockup. iOS 17 crops previews toward
    # square, and a side-by-side layout loses the mark entirely to a centre crop — the card
    # then reads "iddle Groun" with no logo. Centred, every crop keeps the essentials.
    mark = draw_mark(300, padding=0.0)
    card.paste(mark, ((w - mark.width) // 2, 210), mark)

    centred("Middle Ground", 590, font(140, "Bold"), SLATE)
    centred("Meet in the middle.", 760, font(64, "Medium"), INDIGO)
    # Kept under 1096px wide — the usable width of a centre-square crop at this height, less
    # margins. The longer version of this line read well on the full card and lost its last
    # three words on a phone.
    centred("For the plans two people make together.", 900, font(48), WARM_600)
    centred("seekmiddleground.com", 1010, font(44, "SemiBold"), TEAL)
    return card


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    if not INTER.exists():
        raise SystemExit(f"Missing {INTER} — see the module docstring.")
    if not ICON.exists():
        raise SystemExit(f"Missing app icon: {ICON}")

    # Favicon: drawn, tight-cropped, multi-resolution. Browsers and scrapers pick a frame out
    # of the .ico themselves, and a single large frame gets downscaled badly by whoever does.
    draw_mark(256).save(
        ASSETS / "favicon.ico",
        sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    print("  favicon.ico       (drawn, 16–256)")

    if BRAND_FAVICON.exists():
        (ASSETS / "favicon.svg").write_bytes(BRAND_FAVICON.read_bytes())
        print("  favicon.svg")

    icon = Image.open(ICON).convert("RGBA")
    for size, name in [(180, "apple-touch-icon.png"), (192, "icon-192.png"), (512, "icon-512.png")]:
        opaque(icon, size).save(ASSETS / name, optimize=True)
        print(f"  {name}")

    social_card().save(ASSETS / "og-image-v1.png", optimize=True)
    print("  og-image-v1.png   (2400×1256)")

    total = sum(p.stat().st_size for p in ASSETS.rglob("*") if p.is_file())
    print(f"\nsite/assets: {total // 1024} KB")


if __name__ == "__main__":
    main()
