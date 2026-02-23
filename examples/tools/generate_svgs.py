#!/usr/bin/env python3
"""Generate simple SVG assets for the Typst example."""

from __future__ import annotations

import os
import sys


def _write(path: str, body: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(body)


def _diamond_svg() -> str:
    return """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200">
  <rect width="200" height="200" fill="#f5f8ff"/>
  <polygon points="100,15 185,100 100,185 15,100" fill="#4b7bec" stroke="#274b8f" stroke-width="6"/>
  <circle cx="100" cy="100" r="18" fill="#ffffff"/>
</svg>
"""


def _stripes_svg() -> str:
    return """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200">
  <rect width="200" height="200" fill="#fff7ec"/>
  <rect y="10" width="200" height="20" fill="#f4a261"/>
  <rect y="50" width="200" height="20" fill="#e76f51"/>
  <rect y="90" width="200" height="20" fill="#2a9d8f"/>
  <rect y="130" width="200" height="20" fill="#264653"/>
  <rect y="170" width="200" height="20" fill="#e9c46a"/>
</svg>
"""


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("expected two output paths", file=sys.stderr)
        return 1

    diamond_out, stripes_out = argv
    _write(diamond_out, _diamond_svg())
    _write(stripes_out, _stripes_svg())
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
