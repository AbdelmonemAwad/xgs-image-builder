#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Abdelmonem Awad <eg2@live.com>
"""Draw the README's banner, in a dark and a light version.

    python3 tools/readme-art.py

Writes docs/images/banner-{dark,light}.svg. The README shows the one that matches the reader's GitHub
theme through <picture>. The drawing is the one os-xgs-npu's README and the author's profile use - the
same palette, the same rule and type - so the three read as one family.

The board of the two appliances under it is not drawn here. It is os-xgs-npu's own, read from that
repository, so it is always that project's current state and never a copy that has gone stale.
"""
import pathlib

OUT = pathlib.Path(__file__).resolve().parent.parent / 'docs' / 'images'

# The same two palettes as os-xgs-npu's tools/readme-art.py.
THEMES = {
    'dark': dict(bg='#0D1117', card='#161B22', line='#30363D', fg='#E6EDF3', sub='#8B949E',
                 kk='#6E7681', acc='#E3B341', grad='#161B22', dot='#FFFFFF', warn='#F85149',
                 warnbg='#2D1214'),
    'light': dict(bg='#FFFFFF', card='#F6F8FA', line='#D0D7DE', fg='#1F2328', sub='#59636E',
                  kk='#6E7781', acc='#9A6700', grad='#F6F8FA', dot='#1F2328', warn='#CF222E',
                  warnbg='#FFEBE9'),
}
SANS = 'ui-sans-serif,-apple-system,Segoe UI,Inter,Helvetica,Arial,sans-serif'
MONO = 'ui-monospace,SFMono-Regular,Menlo,Consolas,monospace'


def image_tile(t):
    """The build page's own mark - an appliance with a disc beside it - on a tile, 2x."""
    return f'''<g transform="translate(888 50)">
    <rect width="192" height="192" rx="28" fill="{t['card']}" stroke="{t['line']}" stroke-width="2"/>
    <g transform="translate(24 24) scale(6)" fill="none" stroke="{t['acc']}" stroke-width="1.1"
       stroke-linecap="round" stroke-linejoin="round">
      <rect x="2.5" y="6.5" width="19" height="11" rx="2.5"/>
      <path d="M6 10.5h3.5M6 13.5h2"/>
      <circle cx="16.8" cy="12" r="2.3"/>
      <path d="M16.8 7.4v1.2M16.8 15.4v1.2M12.9 12h1.2M19.5 12h1.2"/>
    </g>
  </g>'''


def banner(theme):
    t = THEMES[theme]
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 300" width="1200" height="300" role="img" aria-label="xgs-image-builder - an OPNsense image for a Sophos XGS, with everything inside">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="{t['bg']}"/>
      <stop offset="100%" stop-color="{t['grad']}"/>
    </linearGradient>
    <pattern id="dots" width="22" height="22" patternUnits="userSpaceOnUse">
      <circle cx="1.5" cy="1.5" r="1.1" fill="{t['dot']}" opacity="0.05"/>
    </pattern>
  </defs>
  <rect width="1200" height="300" rx="14" fill="url(#bg)"/>
  <rect width="1200" height="300" rx="14" fill="url(#dots)"/>
  {image_tile(t)}
  <g fill="none" stroke="{t['acc']}" stroke-width="1.5">
    <path d="M984 256 L1060 274 L984 292 L908 274 Z" opacity="0.4"/>
  </g>
  <rect x="80" y="96" width="4" height="108" rx="2" fill="{t['acc']}"/>
  <text x="108" y="140" font-family="{SANS}" font-size="54" font-weight="700" fill="{t['fg']}" letter-spacing="-1">xgs-image-builder</text>
  <text x="110" y="182" font-family="{SANS}" font-size="22" font-weight="500" fill="{t['sub']}">An OPNsense image for a Sophos XGS, with everything inside</text>
  <text x="110" y="216" font-family="{MONO}" font-size="15" fill="{t['kk']}">the official image, verified &#183; os-xgs-npu &#183; four plugins &#183; Arabic &amp; RTL</text>
</svg>
'''


# The security notice under the banner, while there is one - the same card as os-xgs-npu's, in words
# for the images. The README's caution block under it carries the links and the detail.
NOTICE = {
    'title': 'Update OPNsense right after installing - PHP2Shell',
    'chip': 'CRITICAL &#183; CVE-2026-109618 &#183; CVE-2026-109619',
    'lines': [
        ('Every image here starts from OPNsense 26.7&#8217;s own image and carries its PHP - older than the fix.', 'fg'),
        ('Two PHP flaws can let code run on the firewall without a login, and its web interface runs on PHP.', 'sub'),
        ('First boot: System &#8250; Firmware &#8250; Status &#8250; Check for updates &#8250; Update - a test appliance too.', 'fg'),
        ('The version still reads 26.7.7 afterwards: the PHP version is what tells.', 'sub'),
    ],
    'check': 'php -v  &#8594;  8.5.12 or later',
}


def text(x, y, s, size, fill, weight=400, mono=False, extra=''):
    return (f'<text x="{x}" y="{y}" font-family="{MONO if mono else SANS}" font-size="{size}" '
            f'font-weight="{weight}" fill="{fill}"{extra}>{s}</text>')


def notice(theme):
    t = THEMES[theme]
    n = NOTICE
    h = 300
    lines = ''.join(text(150, 136 + 30 * i, s, 17, t[c]) + '\n  ' for i, (s, c) in enumerate(n['lines']))
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 {h}" width="1200" height="{h}" role="img" aria-label="{n['title']}: update OPNsense to PHP 8.5.12 or later at the first boot, test appliances included">
  <rect x="1" y="1" width="1198" height="{h - 2}" rx="14" fill="{t['warnbg']}" stroke="{t['warn']}" stroke-width="2"/>
  <rect x="1" y="1" width="10" height="{h - 2}" rx="5" fill="{t['warn']}"/>
  <g transform="translate(52 44)">
    <path d="M36 4 L70 64 L2 64 Z" fill="none" stroke="{t['warn']}" stroke-width="5" stroke-linejoin="round"/>
    <rect x="33" y="24" width="6" height="22" rx="3" fill="{t['warn']}"/>
    <circle cx="36" cy="54" r="3.6" fill="{t['warn']}"/>
  </g>
  {text(150, 74, n['title'], 32, t['fg'], 700, extra=' letter-spacing="-0.5"')}
  {text(152, 102, n['chip'], 14, t['warn'], 600, mono=True)}
  {lines}<rect x="150" y="{h - 52}" width="380" height="34" rx="8" fill="{t['card']}" stroke="{t['line']}"/>
  {text(166, h - 29, n['check'], 15, t['fg'], mono=True)}
</svg>
'''


if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    for theme in THEMES:
        (OUT / f'banner-{theme}.svg').write_text(banner(theme), encoding='utf-8', newline='\n')
        (OUT / f'notice-{theme}.svg').write_text(notice(theme), encoding='utf-8', newline='\n')
    print(f'wrote {OUT}/{{banner,notice}}-{{dark,light}}.svg')
