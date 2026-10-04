#!/usr/bin/env python3
#-
# SPDX-License-Identifier: BSD-2-Clause
#
"""Check that the build page offers exactly what the workflow accepts.

There are two lists of choices in this repository and there have to be: GitHub renders a workflow's
own `workflow_dispatch` inputs, and a static page cannot read them. So `docs/index.html` carries its
own `<option>` values.

Two lists that must agree and nothing comparing them is the shape of fault this project's sibling
spent weeks on - four datapath constants that were wrong because nothing checked them against the
pages that quoted them. The failure here is quieter than that: the page offers a value, the reader
picks it, the issue is filed, and `tools/read-request.py` refuses it against the workflow's list.
The reader did nothing wrong and there is nothing on the page to tell them so.

`read-request.py` already validates against the workflow rather than a copy, so the workflow and the
parser cannot drift. This closes the one remaining pair.

    tools/check-options.py [repository root]

Exit status is 0 when they agree, 1 when they do not.
"""
import os
import re
import sys


def workflow_options(path):
    """Every choice input's option list, read out of the workflow."""
    out = {}
    name = None
    in_inputs = False
    with open(path, encoding='utf-8') as fh:
        for line in fh:
            if re.match(r'^\s{4}inputs:\s*$', line):
                in_inputs = True
                continue
            if in_inputs and re.match(r'^\S', line):
                break
            if not in_inputs:
                continue
            m = re.match(r'^\s{6}(\w+):\s*$', line)
            if m:
                name = m.group(1)
                continue
            m = re.match(r'^\s+options:\s*\[(.*)\]\s*$', line)
            if m and name:
                out[name] = [v.strip().strip('\'"') for v in m.group(1).split(',') if v.strip()]
    return out


def page_options(path):
    """Every dropdown's option values, by its id.

    Comments are stripped first. A comment that merely mentions a tag by name is not markup, but
    the scan below cannot tell the difference: a `<select>` written in prose opens a block that
    runs to the first real closing tag and swallows the dropdown in between. That happened, and
    the report was the confusing kind - the page was said to be missing a dropdown that was
    plainly there.
    """
    text = open(path, encoding='utf-8').read()
    text = re.sub(r'<!--.*?-->', '', text, flags=re.S)
    out = {}
    for block in re.finditer(r'<select\b([^>]*)>(.*?)</select>', text, re.S | re.I):
        attrs, inner = block.group(1), block.group(2)
        m = re.search(r'\bid\s*=\s*["\']([^"\']+)["\']', attrs)
        if not m:
            continue
        out[m.group(1)] = re.findall(r'<option\b[^>]*\bvalue\s*=\s*["\']([^"\']*)["\']', inner, re.I)
    return out


def main(argv):
    root = argv[1] if len(argv) > 1 else '.'
    wf = os.path.join(root, '.github', 'workflows', 'build.yml')
    pg = os.path.join(root, 'docs', 'index.html')

    for path in (wf, pg):
        if not os.path.isfile(path):
            print('%s does not exist' % path)
            return 1

    want = workflow_options(wf)
    have = page_options(pg)

    if not want:
        print('no choice inputs found in %s - has its shape changed?' % wf)
        return 1

    bad = []
    for name in sorted(want):
        if name not in have:
            bad.append('%s: the workflow offers %s, the page has no <select id="%s">'
                       % (name, want[name], name))
        elif have[name] != want[name]:
            bad.append('%s: workflow %s, page %s' % (name, want[name], have[name]))
    for name in sorted(set(have) - set(want)):
        bad.append('%s: the page offers %s, the workflow has no such choice input'
                   % (name, have[name]))

    if bad:
        print('The build page and the workflow do not offer the same choices:')
        for line in bad:
            print('  %s' % line)
        print()
        print('A reader can pick a value the build will then refuse, with nothing on the page')
        print('saying so. Change both, or neither.')
        return 1

    total = sum(len(v) for v in want.values())
    print('%d choice input(s), %d option(s), page and workflow agree.' % (len(want), total))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
