#!/usr/bin/env python3
#-
# SPDX-License-Identifier: BSD-2-Clause
#
"""Refuse a workflow that interpolates a value into shell source.

GitHub substitutes `${{ ... }}` into the text of a `run:` block BEFORE any shell sees it. The shell
is then handed a program it did not expect: whatever the value contains is code, not data.

This repository learned it the expensive way. The first build that ever ran died, and so did the
step that was supposed to explain the death, both with the same error:

    sh: Syntax error: "(" unexpected

The value was the subject of a commit in the project being installed:

    Take npuep's shape for the receive filters and delete the rest (#228)

written into `'...'` in the script. The apostrophe in `npuep's` closed the string, and `(#228)` was
left standing on its own as code. Nobody wrote anything malicious; somebody wrote English.

The same shape with a `"` or a `$(` in it is not a syntax error, it is a command on the runner.

THE FIX IS NOT QUOTING IT BETTER. There is no quoting that survives a value chosen by someone else,
because the quoting is part of the same text the value is pasted into. The value has to arrive as
data: `env:` on the step, `$NAME` in the script. For a step that runs in a guest, the action's own
`envs:` list carries the names across.

So this allows no exceptions. `${{ }}` is fine in `if:`, in `with:`, in `env:` - everywhere a value
is a value. It is never fine inside a `run:`.

    tools/check-no-interpolation.py [repository root]

Exit status is 0 when no workflow does it, 1 when one does.
"""
import os
import re
import sys

EXPR = re.compile(r'\$\{\{.*?\}\}', re.S)


def runs(path):
    """Every shell body in a workflow, with the line it starts on.

    A hand-rolled scan rather than a YAML parse: a parser gives the string but not the line it came
    from, and a report that cannot be clicked is a report nobody acts on. `run:` appears as a step
    key and, for an action that runs a script in a guest, under `with:`. Both are shell.
    """
    out = []
    lines = open(path, encoding='utf-8').read().split('\n')
    i = 0
    while i < len(lines):
        m = re.match(r'^(\s*)-?\s*run:\s*[|>]?[-+]?\s*$', lines[i])
        if not m:
            i += 1
            continue
        indent = len(m.group(1))
        start = i + 1
        body = []
        j = i + 1
        while j < len(lines):
            line = lines[j]
            if line.strip() and (len(line) - len(line.lstrip())) <= indent:
                break
            body.append((j + 1, line))
            j += 1
        out.append((start, body))
        i = j
    return out


def main(argv):
    root = argv[1] if len(argv) > 1 else '.'
    where = os.path.join(root, '.github', 'workflows')
    if not os.path.isdir(where):
        print('%s does not exist' % where)
        return 1

    bad = []
    seen = 0
    for name in sorted(os.listdir(where)):
        if not name.endswith(('.yml', '.yaml')):
            continue
        path = os.path.join(where, name)
        seen += 1
        for _, body in runs(path):
            for lineno, line in body:
                for expr in EXPR.findall(line):
                    bad.append((os.path.join('.github', 'workflows', name), lineno,
                                ' '.join(expr.split()), line.strip()))

    if bad:
        print('A workflow pastes a value into shell source. The shell receives it as code:')
        print()
        for path, lineno, expr, line in bad:
            print('  %s:%d' % (path, lineno))
            print('      %s' % line[:96])
            print('      %s' % expr)
        print()
        print('%d place(s). Pass each one through `env:` on the step and read it as $NAME in the' % len(bad))
        print('script. A step that runs inside a guest also needs the name in the action\'s `envs:`.')
        return 1

    print('%d workflow(s) checked, no value pasted into shell source.' % seen)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
