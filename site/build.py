#!/usr/bin/env python3
"""Render seekmiddleground.com from Markdown into a static site.

One generator for every page — the legal documents and the investor-facing ones alike. That is
deliberate: two templates drift, and a Privacy Policy that looks nothing like the homepage is
exactly the unprofessional result this site exists to avoid.

Deliberately dependency-free (no pandoc, no markdown package, no static-site framework) so it
runs anywhere with a bare python3, and supports only the Markdown subset these documents use:
headings, paragraphs, bold/italic/code spans, links, bullet lists, blockquotes, tables,
horizontal rules — plus raw HTML passthrough, which is what lets the homepage have a real
layout without dragging in a templating engine.

Usage:  python3 site/build.py
Output: site/dist/ — committed, and served verbatim by both Railway and Firebase Hosting.
"""

from __future__ import annotations

import html
import re
import shutil
from datetime import date
from pathlib import Path

HERE = Path(__file__).parent
REPO = HERE.parent
CONTENT = HERE / "content"
ASSETS = HERE / "assets"
DIST = HERE / "dist"
LEGAL = REPO / "docs" / "legal"

SITE_URL = "https://seekmiddleground.com"
SITE_NAME = "Middle Ground"
OG_IMAGE = f"{SITE_URL}/og-image-v1.png"
# Versioned in the filename because Apple's link-preview cache cannot be purged by
# anyone. A bad card at a fixed path is permanent; a bad card at -v1 is fixed by -v2.
OG_WIDTH, OG_HEIGHT = 2400, 1256


class Page:
    """One output page.

    `source` is a path so the legal Markdown can stay at docs/legal/ — those files are the
    published source of truth and keep their own history, rather than being copied in here.
    """

    def __init__(self, slug: str, title: str, description: str, source: Path, nav: str = ""):
        self.slug = slug
        self.title = title
        self.description = description
        self.source = source
        self.nav = nav  # which nav item to mark current; empty means none

    @property
    def url(self) -> str:
        return f"{SITE_URL}/" if self.slug == "index" else f"{SITE_URL}/{self.slug}"

    @property
    def filename(self) -> str:
        return f"{self.slug}.html"


PAGES = [
    Page(
        "index",
        "Middle Ground",
        "The app for plans you make with other people. Dinner, the weekend, "
        "who\u2019s actually free on Thursday.",
        CONTENT / "index.md",
        nav="product",
    ),
    Page(
        "changelog",
        "Changelog",
        "Every release of Middle Ground, what changed in it, and when it shipped.",
        CONTENT / "changelog.md",
        nav="changelog",
    ),
    Page(
        "timeline",
        "Timeline",
        "How Middle Ground got here, and what is being built next.",
        CONTENT / "timeline.md",
        nav="timeline",
    ),
    # Slug is `privacy`, not `privacy-policy`: the app and the App Store Connect metadata both
    # link to /privacy, and naming the file after the URL removes the rewrite that existed only
    # to paper over the mismatch. The old paths still 301 — see site/Caddyfile.
    Page(
        "privacy",
        "Privacy Policy",
        "What Middle Ground collects, why, and what it never does with it.",
        LEGAL / "privacy-policy.md",
    ),
    Page(
        "terms",
        "Terms of Service",
        "The terms you agree to when you use Middle Ground.",
        LEGAL / "terms-of-service.md",
    ),
    Page(
        "support",
        "Support",
        "How to get help with Middle Ground, and how to reach a human.",
        LEGAL / "support.md",
    ),
    Page(
        "404",
        "Not found",
        "That page does not exist.",
        CONTENT / "404.md",
    ),
]


# ---------------------------------------------------------------- the mark

# The logo mark, inline rather than an <img>: it is small, it must render before first paint,
# and an inline SVG inherits currentColor so it adapts to the colour scheme. Geometry matches
# brand/logo-mark.svg and LogoMark.swift exactly — two figures and a heart in a 512 space.
MARK = """<svg viewBox="0 0 512 512" width="{size}" height="{size}" aria-hidden="true" focusable="false">
<circle cx="170" cy="130" r="48" fill="var(--indigo)"/>
<rect x="95" y="190" width="160" height="280" rx="80" fill="var(--indigo)"/>
<circle cx="342" cy="130" r="48" fill="var(--teal)"/>
<rect x="257" y="190" width="160" height="280" rx="80" fill="var(--teal)"/>
<path d="M256 340 C256 340, 190 285, 190 235 C190 185, 230 170, 256 210 C282 170, 322 185, 322 235 C322 285, 256 340, 256 340 Z" fill="var(--coral)"/>
</svg>"""


TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<!-- Build numbers are twelve-digit strings, and iOS Safari helpfully turns those into tappable
     phone links — the changelog rendered with every version underlined in blue. -->
<meta name="format-detection" content="telephone=no">
<title>{head_title}</title>
<meta name="description" content="{description}">
<link rel="canonical" href="{url}">

<!-- Open Graph. Apple Messages reads these, and it reads them absolutely: a relative
     og:image yields a bare grey card with no explanation of why. -->
<meta property="og:type" content="website">
<meta property="og:locale" content="en_US">
<meta property="og:site_name" content="{site_name}">
<meta property="og:title" content="{og_title}">
<meta property="og:description" content="{description}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{og_image}">
<!-- secure_url as well as url: some parsers (older Facebook-derived ones, which is most of
     them) look for it specifically and fall back to no image when it is absent. -->
<meta property="og:image:secure_url" content="{og_image}">
<meta property="og:image:type" content="image/png">
<meta property="og:image:width" content="{og_width}">
<meta property="og:image:height" content="{og_height}">
<meta property="og:image:alt" content="Middle Ground — meet in the middle.">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{og_title}">
<meta name="twitter:description" content="{description}">
<meta name="twitter:image" content="{og_image}">

<link rel="icon" href="/favicon.ico" sizes="32x32">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/site.webmanifest">
<meta name="theme-color" content="#F7F6F3" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#1E293B" media="(prefers-color-scheme: dark)">
<style>
{css}
</style>
</head>
<body class="page-{slug}">
<a class="skip" href="#main">Skip to content</a>

<header class="site">
  <div class="wrap bar">
    <a class="brand" href="/">{mark}<span>Middle Ground</span></a>
    <nav aria-label="Primary">
      <a href="/"{nav_product}>Product</a>
      <a href="/changelog"{nav_changelog}>Changelog</a>
      <a href="/timeline"{nav_timeline}>Timeline</a>
    </nav>
  </div>
</header>

<main id="main" class="wrap">
{body}
</main>

<footer class="site">
  <div class="wrap">
    <div class="foot-brand">{mark_small}<span>Middle Ground</span></div>
    <nav aria-label="Footer">
      <a href="/privacy">Privacy</a>
      <a href="/terms">Terms</a>
      <a href="/support">Support</a>
      <a href="mailto:support@middleground.app">Contact</a>
    </nav>
    <p class="copyright">© {year} Middle Ground. Made with care.</p>
  </div>
</footer>
</body>
</html>
"""


CSS = """
:root {
  --indigo:#6366F1; --teal:#14B8A6; --coral:#FF8FA3;
  --sunshine:#FFC857; --lavender:#A78BFA;
  --sand:#F7F6F3; --surface:#FFFFFF;
  --warm-100:#F0EFEC; --warm-200:#E4E3E0; --warm-400:#A1A1AA; --warm-600:#71717A;
  --slate:#334155;
  --shadow:rgba(51,65,85,.07); --shadow-lg:rgba(51,65,85,.10);
}
@media (prefers-color-scheme: dark) {
  :root {
    --indigo:#818CF8; --teal:#2DD4BF; --coral:#FDA4AF;
    --sunshine:#FDE68A; --lavender:#C4B5FD;
    --sand:#1E293B; --surface:#334155;
    --warm-100:#475569; --warm-200:#64748B; --warm-400:#94A3B8; --warm-600:#CBD5E1;
    --slate:#F8FAFC;
    --shadow:rgba(0,0,0,.22); --shadow-lg:rgba(0,0,0,.30);
  }
}

*, *::before, *::after { box-sizing:border-box; }

/* System fonts, not webfonts. This link gets opened from a text message on a phone, where a
   render-blocking font request is the difference between instant and not — and -apple-system
   is the same family the app itself uses. */
html { -webkit-text-size-adjust:100%; scroll-behavior:smooth; }
@media (prefers-reduced-motion: reduce) { html { scroll-behavior:auto; } }

body {
  margin:0;
  background:var(--sand);
  color:var(--slate);
  font:16px/1.65 -apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",Roboto,Helvetica,Arial,sans-serif;
  font-synthesis-weight:none;
}

.wrap { width:100%; max-width:760px; margin:0 auto; padding:0 24px; }

.skip {
  position:absolute; left:-9999px; top:0; background:var(--indigo); color:#fff;
  padding:10px 16px; border-radius:0 0 8px 0; z-index:10;
}
.skip:focus { left:0; }

/* ------------------------------------------------------------------ chrome */

header.site {
  position:sticky; top:0; z-index:5;
  background:color-mix(in srgb, var(--sand) 88%, transparent);
  backdrop-filter:saturate(180%) blur(14px);
  -webkit-backdrop-filter:saturate(180%) blur(14px);
  border-bottom:1px solid var(--warm-200);
}
header.site .bar {
  display:flex; align-items:center; justify-content:space-between; gap:16px;
  min-height:60px;
}
.brand {
  display:inline-flex; align-items:center; gap:9px;
  font-weight:700; font-size:16px; letter-spacing:-.01em;
  color:var(--slate); text-decoration:none;
}
.brand svg { display:block; }
header.site nav { display:flex; gap:4px; }
header.site nav a {
  color:var(--warm-600); text-decoration:none; font-size:14px; font-weight:550;
  padding:7px 11px; border-radius:8px; white-space:nowrap;
}
header.site nav a:hover { color:var(--slate); background:var(--warm-100); }
header.site nav a[aria-current] { color:var(--indigo); background:var(--warm-100); }

footer.site {
  margin-top:96px; padding:40px 0 56px;
  border-top:1px solid var(--warm-200);
}
footer.site .foot-brand {
  display:inline-flex; align-items:center; gap:8px;
  font-weight:700; font-size:15px; color:var(--slate);
}
footer.site nav { display:flex; flex-wrap:wrap; gap:18px; margin:14px 0 18px; }
footer.site nav a { color:var(--warm-600); text-decoration:none; font-size:14px; }
footer.site nav a:hover { color:var(--indigo); text-decoration:underline; }
.copyright { margin:0; color:var(--warm-400); font-size:13px; }

/* ---------------------------------------------------------------- typography */

main { padding-top:8px; }
h1, h2, h3 { letter-spacing:-.022em; line-height:1.15; font-weight:700; }
h1 { font-size:clamp(32px, 6vw, 44px); margin:36px 0 12px; }
h2 { font-size:clamp(22px, 3.6vw, 27px); margin:56px 0 12px; }
h3 { font-size:18px; font-weight:650; margin:32px 0 6px; }
p, li { color:var(--slate); }
p { margin:0 0 16px; }
a { color:var(--indigo); text-decoration-thickness:1px; text-underline-offset:2px; }
strong { font-weight:650; }
ul { padding-left:22px; margin:0 0 16px; }
li { margin:0 0 7px; }
code {
  background:var(--warm-100); padding:2px 6px; border-radius:6px;
  font:.88em/1 ui-monospace,SFMono-Regular,Menlo,monospace;
}
hr { border:0; border-top:1px solid var(--warm-200); margin:48px 0; }
blockquote {
  margin:0 0 20px; padding:2px 0 2px 18px;
  border-left:3px solid var(--warm-200); color:var(--warm-600);
}
table { border-collapse:collapse; width:100%; margin:0 0 20px; font-size:15px; }
th, td { text-align:left; padding:9px 12px; border-bottom:1px solid var(--warm-200); }
th { font-weight:650; color:var(--warm-600); font-size:13px; text-transform:uppercase; letter-spacing:.04em; }

.lede { font-size:19px; line-height:1.6; color:var(--warm-600); margin:0 0 24px; }

/* --------------------------------------------------------------------- hero */

.hero { padding:56px 0 8px; }
.hero .eyebrow {
  display:inline-flex; align-items:center; gap:7px;
  font-size:13px; font-weight:600; letter-spacing:.01em;
  color:var(--indigo); background:var(--warm-100);
  padding:6px 12px; border-radius:999px; margin-bottom:20px;
}
.hero .eyebrow::before {
  content:""; width:7px; height:7px; border-radius:50%;
  background:var(--teal); flex:none;
}
.hero h1 { font-size:clamp(36px, 7.4vw, 56px); margin:0 0 16px; }
.hero .tagline {
  background:linear-gradient(105deg, var(--indigo), var(--teal));
  -webkit-background-clip:text; background-clip:text; color:transparent;
}
.hero p { font-size:clamp(17px, 2.6vw, 20px); line-height:1.55; color:var(--warm-600); max-width:34em; }

.actions { display:flex; flex-wrap:wrap; gap:12px; margin:28px 0 8px; }
.btn {
  display:inline-flex; align-items:center; gap:8px;
  padding:12px 20px; border-radius:12px; font-size:15px; font-weight:600;
  text-decoration:none; border:1px solid transparent;
}
.btn-primary { background:var(--indigo); color:#fff; box-shadow:0 6px 18px -6px var(--indigo); }
.btn-primary:hover { filter:brightness(1.06); }
.btn-secondary { background:var(--surface); color:var(--slate); border-color:var(--warm-200); }
.btn-secondary:hover { border-color:var(--warm-400); }

/* -------------------------------------------------------------------- cards */

.cards { display:grid; gap:14px; grid-template-columns:repeat(auto-fit, minmax(220px,1fr)); margin:24px 0 8px; }
.card {
  background:var(--surface); border:1px solid var(--warm-200); border-radius:16px;
  padding:20px; box-shadow:0 1px 2px var(--shadow);
}
.card h3 { margin:0 0 6px; font-size:16px; }
.card p { margin:0; font-size:14.5px; color:var(--warm-600); line-height:1.55; }
.card .ico { font-size:20px; line-height:1; display:block; margin-bottom:12px; }

/* ---------------------------------------------------------------- changelog */

.release {
  background:var(--surface); border:1px solid var(--warm-200); border-radius:16px;
  padding:22px 24px; margin:0 0 16px; box-shadow:0 1px 2px var(--shadow);
}
.release-head { display:flex; flex-wrap:wrap; align-items:baseline; gap:10px; margin-bottom:4px; }
.release-version {
  font-size:17px; font-weight:700; letter-spacing:-.01em; color:var(--slate);
}
.release-build {
  font:12px/1 ui-monospace,SFMono-Regular,Menlo,monospace;
  color:var(--warm-600); background:var(--warm-100);
  padding:5px 8px; border-radius:6px;
}
.release-date { font-size:13px; color:var(--warm-400); margin-left:auto; }
.release ul { margin:12px 0 0; padding-left:20px; }
.release li { font-size:15px; color:var(--warm-600); margin-bottom:6px; }
.release li strong { color:var(--slate); font-weight:600; }
.release.current { border-color:var(--indigo); box-shadow:0 6px 22px -12px var(--indigo); }
.tag {
  font-size:11px; font-weight:700; letter-spacing:.05em; text-transform:uppercase;
  color:var(--teal); border:1px solid currentColor; padding:3px 7px; border-radius:5px;
}

/* --------------------------------------------------------------- screenshots */

/* Screenshots sit beside the words rather than above them, so a release entry still scans as
   a list. On a phone they stack, because a 200px-wide image next to text is neither. */
.shot {
  flex:none; width:190px; margin:0;
  border-radius:18px; overflow:hidden;
  border:1px solid var(--warm-200);
  background:var(--surface);
  box-shadow:0 8px 28px -14px var(--shadow-lg);
}
.shot img { display:block; width:100%; height:auto; }
.shot figcaption {
  font-size:11.5px; color:var(--warm-400); text-align:center;
  padding:7px 8px 9px; border-top:1px solid var(--warm-200);
}
.with-shot { display:flex; gap:22px; align-items:flex-start; }
.with-shot > :first-child { flex:1; min-width:0; }

.shot-row {
  display:flex; gap:16px; overflow-x:auto; padding:4px 0 10px;
  scroll-snap-type:x mandatory; -webkit-overflow-scrolling:touch;
}
.shot-row .shot { scroll-snap-align:start; }

@media (max-width:640px) {
  /* column-reverse, not block: the figure is last in the markup so that a reader without CSS
     gets the words first, but on a phone the image has to lead — stacked normally it sat below
     a dozen bullets and nobody scrolled far enough to see it. */
  .with-shot { flex-direction:column-reverse; gap:0; }
  .with-shot .shot { width:100%; max-width:230px; align-self:center; margin:0 0 18px; }
}

/* ----------------------------------------------------------------- timeline */

.timeline { list-style:none; padding:0; margin:24px 0 8px; position:relative; }
.timeline::before {
  content:""; position:absolute; left:7px; top:8px; bottom:8px;
  width:2px; background:var(--warm-200); border-radius:2px;
}
.timeline li { position:relative; padding:0 0 26px 34px; margin:0; }
/* A milestone with a thumbnail becomes a two-column row. Deliberately small: the timeline
   earns its keep by being scannable, and full-size phone screenshots would turn it into a
   second changelog. */
.timeline li.has-shot { display:flex; gap:16px; align-items:flex-start; }
.timeline li.has-shot > div { flex:1; min-width:0; }
.timeline .shot.tiny { width:96px; flex:none; border-radius:12px; }
.timeline .shot.tiny figcaption { display:none; }
.timeline .shot.tiny a { display:block; }
.timeline .shot.tiny:hover { border-color:var(--indigo); }
@media (max-width:520px) { .timeline .shot.tiny { width:74px; } }
.timeline li::before {
  content:""; position:absolute; left:0; top:6px;
  width:16px; height:16px; border-radius:50%;
  background:var(--surface); border:3px solid var(--warm-400);
}
.timeline li.done::before { border-color:var(--teal); background:var(--teal); }
.timeline li.now::before { border-color:var(--indigo); background:var(--surface); box-shadow:0 0 0 4px color-mix(in srgb, var(--indigo) 18%, transparent); }
.timeline .when {
  display:block; font-size:12px; font-weight:650; letter-spacing:.05em;
  text-transform:uppercase; color:var(--warm-400); margin-bottom:3px;
}
.timeline .what { font-weight:650; color:var(--slate); display:block; margin-bottom:3px; }
.timeline p { margin:0; font-size:15px; color:var(--warm-600); }

/* --------------------------------------------------------------- responsive */

@media (max-width:560px) {
  .wrap { padding:0 18px; }
  header.site nav a { padding:7px 8px; font-size:13.5px; }
  .brand span { display:none; }
  .release { padding:18px; }
  .release-date { margin-left:0; width:100%; }
}
"""


# ------------------------------------------------------------- markdown

def inline(text: str) -> str:
    """Escape, then apply inline Markdown. Code spans are protected from other rules."""
    out = html.escape(text, quote=False)
    codes: list[str] = []

    def stash(match: re.Match[str]) -> str:
        codes.append(match.group(1))
        return f"\x00{len(codes) - 1}\x00"

    out = re.sub(r"`([^`]+)`", stash, out)
    out = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', out)
    out = re.sub(r"&lt;(https?://[^\s&]+)&gt;", r'<a href="\1">\1</a>', out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<em>\1</em>", out)
    for i, code in enumerate(codes):
        out = out.replace(f"\x00{i}\x00", f"<code>{code}</code>")
    return out


def is_block_start(line: str) -> bool:
    """True when a line begins a non-paragraph block.

    Must mirror the branches in `render` exactly. A loose character class here is a trap:
    `**Bold**` starts with `*` but is a paragraph, and treating it as a block start makes the
    paragraph loop consume nothing and spin forever.
    """
    s = line.strip()
    return (
        s.startswith("|")
        or s.startswith("> ")
        or s.startswith("<")
        or bool(re.match(r"^[-*] ", s))
        or s.startswith("#")
        or (set(s) <= set("-") and len(s) >= 3)
    )


def render(md: str) -> str:
    lines = md.split("\n")
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if not stripped:
            i += 1
            continue

        # Raw HTML passthrough. This is what lets the homepage have a hero and a card grid
        # without a templating engine, while the legal pages stay plain Markdown. A block runs
        # until a blank line, so authored HTML must not contain one.
        if stripped.startswith("<"):
            block = []
            while i < len(lines) and lines[i].strip():
                block.append(lines[i])
                i += 1
            out.append("\n".join(block))
            continue

        if stripped.startswith("|"):  # table
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append(lines[i].strip())
                i += 1
            if len(rows) >= 2:
                head = [c.strip() for c in rows[0].strip("|").split("|")]
                body = rows[2:]
                out.append("<table><thead><tr>")
                out.extend(f"<th>{inline(c)}</th>" for c in head)
                out.append("</tr></thead><tbody>")
                for row in body:
                    cells = [c.strip() for c in row.strip("|").split("|")]
                    out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in cells) + "</tr>")
                out.append("</tbody></table>")
            continue

        if stripped.startswith("> "):  # blockquote
            quote = []
            while i < len(lines) and lines[i].strip().startswith("> "):
                quote.append(lines[i].strip()[2:])
                i += 1
            out.append(f"<blockquote><p>{inline(' '.join(quote))}</p></blockquote>")
            continue

        if re.match(r"^[-*] ", stripped):  # bullet list
            items = []
            while i < len(lines) and re.match(r"^[-*] ", lines[i].strip()):
                items.append(lines[i].strip()[2:])
                i += 1
            out.append("<ul>")
            out.extend(f"<li>{inline(item)}</li>" for item in items)
            out.append("</ul>")
            continue

        if stripped.startswith("#"):  # heading
            level = len(stripped) - len(stripped.lstrip("#"))
            text = stripped[level:].strip()
            level = min(level, 4)
            out.append(f"<h{level}>{inline(text)}</h{level}>")
            i += 1
            continue

        if set(stripped) <= set("-") and len(stripped) >= 3:  # horizontal rule
            out.append("<hr>")
            i += 1
            continue

        para = []  # paragraph
        while i < len(lines) and lines[i].strip() and not is_block_start(lines[i]):
            para.append(lines[i].strip())
            i += 1
        if para:
            out.append(f"<p>{inline(' '.join(para))}</p>")
        else:
            # Guarantee forward progress; without this an unhandled block start loops forever.
            i += 1

    return "\n".join(out)


# ---------------------------------------------------------------- output

def build_page(page: Page) -> str:
    md = page.source.read_text(encoding="utf-8")
    current = ' aria-current="page"'
    return TEMPLATE.format(
        head_title=page.title if page.slug == "index" else f"{page.title} — {SITE_NAME}",
        og_title=page.title if page.slug == "index" else f"{page.title} — {SITE_NAME}",
        description=html.escape(page.description, quote=True),
        url=page.url,
        site_name=SITE_NAME,
        og_image=OG_IMAGE,
        og_width=OG_WIDTH,
        og_height=OG_HEIGHT,
        css=CSS.strip(),
        slug=page.slug,
        mark=MARK.format(size=26),
        mark_small=MARK.format(size=22),
        nav_product=current if page.nav == "product" else "",
        nav_changelog=current if page.nav == "changelog" else "",
        nav_timeline=current if page.nav == "timeline" else "",
        body=render(md),
        year=date.today().year,
    )


def write_sitemap() -> None:
    urls = "\n".join(
        f"  <url><loc>{p.url}</loc></url>" for p in PAGES if p.slug != "404"
    )
    (DIST / "sitemap.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        f"{urls}\n"
        "</urlset>\n",
        encoding="utf-8",
    )
    # Indexing is wanted: this page exists to be found and forwarded.
    (DIST / "robots.txt").write_text(
        f"User-agent: *\nAllow: /\n\nSitemap: {SITE_URL}/sitemap.xml\n", encoding="utf-8"
    )


def write_manifest() -> None:
    (DIST / "site.webmanifest").write_text(
        '{\n'
        '  "name": "Middle Ground",\n'
        '  "short_name": "Middle Ground",\n'
        '  "icons": [\n'
        '    { "src": "/icon-192.png", "sizes": "192x192", "type": "image/png" },\n'
        '    { "src": "/icon-512.png", "sizes": "512x512", "type": "image/png" }\n'
        '  ],\n'
        '  "theme_color": "#F7F6F3",\n'
        '  "background_color": "#F7F6F3",\n'
        '  "display": "standalone"\n'
        '}\n',
        encoding="utf-8",
    )


def main() -> None:
    DIST.mkdir(parents=True, exist_ok=True)
    if DIST.exists():
        shutil.rmtree(DIST)
    DIST.mkdir(parents=True, exist_ok=True)

    for page in PAGES:
        (DIST / page.filename).write_text(build_page(page), encoding="utf-8")
        print(f"  wrote {page.filename}")

    if ASSETS.exists():
        # Recursive, so `assets/shots/` survives the copy. A flat iterdir silently dropped the
        # screenshots and the pages rendered with broken images.
        for asset in sorted(ASSETS.rglob("*")):
            if not asset.is_file():
                continue
            target = DIST / asset.relative_to(ASSETS)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(asset, target)
            print(f"  copied {asset.relative_to(ASSETS)}")

    write_sitemap()
    write_manifest()
    print("  wrote sitemap.xml, robots.txt, site.webmanifest")
    print(f"\nsite/dist is ready ({len(list(DIST.iterdir()))} files)")


if __name__ == "__main__":
    main()
