#!/usr/bin/env python3
"""Check the board palette against WCAG 2.2 AA. Reads tokens.css, resolves the pairs that components use,
and exits 1 if any text pair is under 4.5:1 or any UI pair (borders, focus ring, stage bars) is under 3:1.
Run from anywhere: python3 board/design/check-contrast.py
"""
import pathlib, re, sys

CSS = (pathlib.Path(__file__).parent / "tokens.css").read_text()

def block(selector_start, selector_end=None):
    """Return the var declarations inside the first block that starts with selector_start."""
    i = CSS.index(selector_start)
    j = CSS.index("{", i); depth = 0; k = j
    while True:
        if CSS[k] == "{": depth += 1
        elif CSS[k] == "}":
            depth -= 1
            if depth == 0: break
        k += 1
    return dict(re.findall(r"(--[\w-]+)\s*:\s*([^;]+);", CSS[j:k]))

def resolve(name, scope, base):
    v = scope.get(name) or base.get(name)
    if v is None: raise KeyError(name)
    v = v.strip()
    m = re.fullmatch(r"var\((--[\w-]+)\)", v)
    return resolve(m.group(1), scope, base) if m else v

def lum(h):
    h = h.lstrip("#"); r, g, b = [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
    f = lambda c: c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)

def ratio(a, b):
    la, lb = lum(a), lum(b); hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)

# (foreground, background, minimum, what it is used for)
PAIRS = [
    ("--md-sys-color-on-surface", "--md-sys-color-surface", 4.5, "body text"),
    ("--md-sys-color-on-surface", "--md-sys-color-surface-container-lowest", 4.5, "card text"),
    ("--md-sys-color-on-surface-variant", "--md-sys-color-surface", 4.5, "secondary text"),
    ("--md-sys-color-on-surface-variant", "--md-sys-color-surface-container-lowest", 4.5, "secondary text on cards"),
    ("--md-sys-color-primary", "--md-sys-color-surface", 4.5, "links, primary text"),
    ("--md-sys-color-primary", "--md-sys-color-surface-container-lowest", 4.5, "links on cards"),
    ("--md-sys-color-on-primary", "--md-sys-color-primary", 4.5, "filled button text"),
    ("--md-sys-color-on-primary-container", "--md-sys-color-primary-container", 4.5, "live chip, selected rail item"),
    ("--md-sys-color-secondary", "--md-sys-color-surface", 4.5, "major severity text"),
    ("--md-sys-color-on-secondary", "--md-sys-color-secondary", 4.5, "rail badge"),
    ("--md-sys-color-on-secondary-container", "--md-sys-color-secondary-container", 4.5, "waiting band, changes chip"),
    ("--md-sys-color-tertiary", "--md-sys-color-surface-container-lowest", 4.5, "tree match text"),
    ("--md-sys-color-on-tertiary-container", "--md-sys-color-tertiary-container", 4.5, "approve chip"),
    ("--md-sys-color-error", "--md-sys-color-surface-container-lowest", 4.5, "blocker severity, tree drift text"),
    ("--md-sys-color-on-error-container", "--md-sys-color-error-container", 4.5, "blocked chip"),
    ("--md-sys-color-inverse-on-surface", "--md-sys-color-inverse-surface", 4.5, "skip link"),
    ("--md-sys-color-outline", "--md-sys-color-surface", 3.0, "outlined chip and button borders"),
    ("--md-sys-color-outline", "--md-sys-color-surface-container-lowest", 3.0, "borders on cards"),
    ("--md-sys-color-primary", "--md-sys-color-surface-container-lowest", 3.0, "focus ring, stage bar done/current"),
    ("--md-sys-color-error", "--md-sys-color-surface-container-lowest", 3.0, "stage bar stopped"),
    ("--md-sys-color-secondary", "--md-sys-color-secondary-container", 3.0, "waiting band accent edge"),
]

base = block(":root {")
dark = block(':root[data-theme="dark"]')
fail = 0
for theme, scope in (("light", {}), ("dark", dark)):
    print(f"== {theme}")
    for fg, bg, need, use in PAIRS:
        try:
            r = ratio(resolve(fg, scope, base), resolve(bg, scope, base))
        except (KeyError, ValueError) as e:
            print(f"  ?? cannot resolve {e} for {use}"); fail = 1; continue
        ok = r >= need
        print(f"  {'ok ' if ok else 'LOW'} {r:5.2f} (need {need}) {use}: {fg} on {bg}")
        fail |= (not ok)
sys.exit(1 if fail else 0)
