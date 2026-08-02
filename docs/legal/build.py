#!/usr/bin/env python3
"""Render the legal Markdown into standalone, brand-styled HTML.

The Markdown files are the source of truth; the HTML is generated so the published pages
cannot drift from them. Deliberately dependency-free (no pandoc / markdown package) so it
runs anywhere, and it only supports the subset of Markdown these documents actually use:
headings, paragraphs, bold/italic/code spans, links, bullet lists, blockquotes, tables and
horizontal rules.

Usage:  python3 docs/legal/build.py
Output: privacy-policy.html, terms-of-service.html, support.html, index.html
"""

from __future__ import annotations

import html
import re
from pathlib import Path

HERE = Path(__file__).parent

PAGES = [
    ("privacy-policy", "Privacy Policy"),
    ("terms-of-service", "Terms of Service"),
    ("support", "Support"),
]

# Brand tokens from brand/design-system.md and brand/dark-mode.css.
TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} — Middle Ground</title>
<meta name="description" content="{title} for Middle Ground, the app for shared decisions.">
<style>
  :root {{
    --indigo:#6366F1; --teal:#14B8A6; --coral:#FF8FA3;
    --sand:#F7F6F3; --surface:#FFFFFF;
    --warm-100:#F0EFEC; --warm-200:#E4E3E0; --warm-600:#71717A; --slate:#334155;
  }}
  @media (prefers-color-scheme: dark) {{
    :root {{
      --indigo:#818CF8; --teal:#2DD4BF; --coral:#FDA4AF;
      --sand:#1E293B; --surface:#334155;
      --warm-100:#475569; --warm-200:#64748B; --warm-600:#CBD5E1; --slate:#F8FAFC;
    }}
  }}
  * {{ box-sizing:border-box; }}
  body {{
    margin:0; padding:0 20px 96px;
    background:var(--sand); color:var(--slate);
    font:16px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
    -webkit-text-size-adjust:100%;
  }}
  .wrap {{ max-width:720px; margin:0 auto; }}
  header {{ padding:48px 0 8px; }}
  .brand {{
    display:inline-flex; align-items:center; gap:10px;
    font-weight:700; letter-spacing:-.01em; color:var(--slate);
    text-decoration:none; font-size:17px;
  }}
  .brand svg {{ display:block; }}
  h1 {{ font-size:34px; line-height:1.2; letter-spacing:-.02em; margin:28px 0 4px; }}
  h2 {{ font-size:22px; letter-spacing:-.01em; margin:40px 0 8px; }}
  h3 {{ font-size:17px; margin:28px 0 4px; }}
  p, li {{ color:var(--slate); }}
  a {{ color:var(--indigo); }}
  strong {{ font-weight:650; }}
  code {{
    background:var(--warm-100); padding:2px 6px; border-radius:6px;
    font:0.9em/1 ui-monospace,SFMono-Regular,Menlo,monospace;
  }}
  hr {{ border:0; border-top:1px solid var(--warm-200); margin:40px 0; }}
  blockquote {{
    margin:24px 0; padding:14px 18px;
    background:var(--surface); border-left:3px solid var(--coral);
    border-radius:0 12px 12px 0;
  }}
  blockquote p {{ margin:0; color:var(--warm-600); }}
  table {{
    width:100%; border-collapse:collapse; margin:20px 0;
    background:var(--surface); border-radius:12px; overflow:hidden;
    display:block; overflow-x:auto; white-space:normal;
  }}
  th, td {{ text-align:left; padding:11px 14px; border-bottom:1px solid var(--warm-100); }}
  th {{ font-size:13px; text-transform:uppercase; letter-spacing:.04em; color:var(--warm-600); }}
  tr:last-child td {{ border-bottom:0; }}
  footer {{
    margin-top:56px; padding-top:20px; border-top:1px solid var(--warm-200);
    color:var(--warm-600); font-size:14px;
  }}
  footer a {{ margin-right:16px; }}
</style>
</head>
<body>
<div class="wrap">
<header>
  <a class="brand" href="index.html">
    <svg width="26" height="26" viewBox="0 0 512 512" aria-hidden="true">
      <circle cx="170" cy="130" r="48" fill="var(--indigo)"/>
      <rect x="95" y="190" width="160" height="280" rx="80" fill="var(--indigo)"/>
      <circle cx="342" cy="130" r="48" fill="var(--teal)"/>
      <rect x="257" y="190" width="160" height="280" rx="80" fill="var(--teal)"/>
      <path d="M256 340C256 340 190 285 190 235c0-50 40-65 66-25 26-40 66-25 66 25 0 50-66 105-66 105z"
            fill="var(--coral)"/>
    </svg>
    Middle Ground
  </a>
</header>
{body}
<footer>
  <a href="privacy-policy.html">Privacy</a>
  <a href="terms-of-service.html">Terms</a>
  <a href="support.html">Support</a>
</footer>
</div>
</body>
</html>
"""


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

        if stripped.startswith("|"):  # table
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append(lines[i].strip())
                i += 1
            cells = [[c.strip() for c in r.strip("|").split("|")] for r in rows]
            # Row 1 is the header; row 2 is the |---|---| separator.
            body_rows = cells[2:] if len(cells) > 1 and set(cells[1][0]) <= set("-: ") else cells[1:]
            out.append("<table><thead><tr>"
                       + "".join(f"<th>{inline(c)}</th>" for c in cells[0])
                       + "</tr></thead><tbody>")
            for row in body_rows:
                out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in row) + "</tr>")
            out.append("</tbody></table>")
            continue

        if stripped.startswith("> "):  # blockquote
            quote = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                quote.append(lines[i].strip().lstrip(">").strip())
                i += 1
            out.append(f"<blockquote><p>{inline(' '.join(quote))}</p></blockquote>")
            continue

        if re.match(r"^[-*] ", stripped):  # bullet list
            items = []
            while i < len(lines) and re.match(r"^[-*] ", lines[i].strip()):
                items.append(lines[i].strip()[2:])
                i += 1
                # Fold indented continuation lines into the same item.
                while i < len(lines) and lines[i].startswith("  ") and lines[i].strip():
                    items[-1] += " " + lines[i].strip()
                    i += 1
            out.append("<ul>" + "".join(f"<li>{inline(t)}</li>" for t in items) + "</ul>")
            continue

        if stripped.startswith("#"):
            level = len(stripped) - len(stripped.lstrip("#"))
            out.append(f"<h{level}>{inline(stripped[level:].strip())}</h{level}>")
            i += 1
            continue

        if set(stripped) <= set("-") and len(stripped) >= 3:
            out.append("<hr>")
            i += 1
            continue

        para = []
        while i < len(lines) and lines[i].strip() and not is_block_start(lines[i]):
            para.append(lines[i].strip())
            i += 1
        if para:
            out.append(f"<p>{inline(' '.join(para))}</p>")
        else:
            # Guarantee forward progress; without this an unhandled block start loops forever.
            i += 1

    return "\n".join(out)


def main() -> None:
    for slug, title in PAGES:
        md = (HERE / f"{slug}.md").read_text(encoding="utf-8")
        # The <h1> comes from the Markdown's own first heading.
        (HERE / f"{slug}.html").write_text(
            TEMPLATE.format(title=title, body=render(md)), encoding="utf-8"
        )
        print(f"  wrote {slug}.html")

    index = """# Middle Ground

**Meet in the Middle.** Middle Ground is an iOS app for shared decisions — it turns everyday
requests into calm, collaborative workflows instead of drawn-out back-and-forth.

## Legal & support

- [Privacy Policy](privacy-policy.html)
- [Terms of Service](terms-of-service.html)
- [Support](support.html)

Questions? Email **support@middleground.app**.
"""
    (HERE / "index.html").write_text(
        TEMPLATE.format(title="Middle Ground", body=render(index)), encoding="utf-8"
    )
    print("  wrote index.html")


if __name__ == "__main__":
    main()
