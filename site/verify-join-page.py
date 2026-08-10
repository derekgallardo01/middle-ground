#!/usr/bin/env python3
"""Checks the join page against the policy that decides whether its script runs.

The invite code lives in the URL and nowhere else, so the join page reads it out with the one
piece of JavaScript on this site. The Content-Security-Policy permits that script by **hash** —
not 'unsafe-inline', not a host — which is the strict way to do it and also a tripwire: change a
byte of the script without updating the Caddyfile and the browser silently refuses to run it. The
page would still render, the fallback copy would still be there, and the only symptom would be
that the highest-friction step in acquisition quietly went back to "read it out of your address
bar". Nobody would see a failure. So this is the failure.

Also asserts the parts that make the page work without JavaScript at all, because that is the
state every visitor is in for the first paint and the state some of them stay in.

Run: python3 site/verify-join-page.py   (builds first, then checks)
"""

import base64
import hashlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DIST = ROOT / "dist"
CADDYFILE = ROOT / "Caddyfile"

# The script's own regex has to accept a real code. Kept in step with
# `Relationship.inviteCodeLength` on the client — six characters is what the app issues.
SAMPLE_PATHS_THAT_SHOULD_MATCH = ["/join/MG24KT", "/join/mg24kt", "/join/MG24KT/"]
SAMPLE_PATHS_THAT_SHOULD_NOT = ["/join", "/join/", "/join/TOOLONG1", "/privacy"]

failures: list[str] = []


def check(condition: bool, message: str) -> None:
    if not condition:
        failures.append(message)


def main() -> int:
    subprocess.run([sys.executable, str(ROOT / "build.py")], check=True, capture_output=True)

    page = (DIST / "join.html").read_text(encoding="utf-8")
    caddyfile = CADDYFILE.read_text(encoding="utf-8")

    scripts = re.findall(r"<script[^>]*>(.*?)</script>", page, re.S)
    check(len(scripts) == 1, f"expected exactly one inline script on the join page, found {len(scripts)}")
    if not scripts:
        print("\n".join(failures))
        return 1

    digest = base64.b64encode(hashlib.sha256(scripts[0].encode()).digest()).decode()
    expected = f"'sha256-{digest}'"
    check(
        expected in caddyfile,
        f"the CSP does not permit the join script. Add {expected} to script-src in site/Caddyfile "
        "(the script changed and the browser would now refuse to run it).",
    )

    # No other page may carry a script: the hash permits exactly this one, so a second script
    # anywhere would be dead code that looks live.
    for other in sorted(DIST.glob("*.html")):
        if other.name == "join.html":
            continue
        check("<script" not in other.read_text(encoding="utf-8"), f"{other.name} has a script tag")

    # Without JavaScript the page must still tell somebody what to do.
    check('id="code-fallback"' in page, "the no-JavaScript fallback paragraph is gone")
    check('id="code-value"' in page, "there is nowhere to put the code")
    check("address in your browser bar" in page, "the fallback no longer explains where the code is")

    # And the extraction has to actually extract. Translated from the JS rather than imported,
    # because there is no JS runtime in this check — kept honest by reading the real source.
    pattern = re.search(r"/\^(.*?)\$/", scripts[0])
    check(pattern is not None, "could not find the path pattern in the script")
    if pattern:
        as_python = pattern.group(1).replace("\\/", "/")
        compiled = re.compile("^" + as_python + "$")
        for path in SAMPLE_PATHS_THAT_SHOULD_MATCH:
            check(compiled.match(path) is not None, f"the script would not read a code from {path}")
        for path in SAMPLE_PATHS_THAT_SHOULD_NOT:
            check(compiled.match(path) is None, f"the script would invent a code for {path}")

    if failures:
        print("join page verification failed:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("join page: script hash matches the CSP, fallback intact, code extraction correct")
    return 0


if __name__ == "__main__":
    sys.exit(main())
