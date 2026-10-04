#!/usr/bin/env python3
#-
# SPDX-License-Identifier: BSD-2-Clause
#
"""Read a build request out of an issue body, and refuse anything build.yml would not accept.

docs/index.html sends a reader to the new-issue form with a fenced JSON block in the body. This
reads that block and writes the values out as workflow outputs.

IT VALIDATES AGAINST build.yml ITSELF, not against a list kept here. The workflow's
workflow_dispatch inputs already name every allowed value, and a second copy of that list is a copy
that goes stale - this repository's own rule about not vendoring a second anything. So the option
lists are read out of the YAML at run time and a value that is not in them is refused.

AND IT IS THE BOUNDARY, which is the other reason it exists. The issue body is written by a person
and ends up in a shell command, so everything that leaves here is either a member of a closed set
or matched against a narrow pattern. The workflow reads the body through the environment rather
than interpolating it into a script, and reads this script's output rather than the body.

Reads ISSUE_BODY from the environment. Writes GITHUB_OUTPUT lines on stdout. Always exits 0: the
workflow decides what to do from `request` and `ok`, so that a refusal is a comment on the issue
rather than a failed run with nothing said.

`request` is false only when the body has no JSON block at all, which means an ordinary issue that
this has no business answering. Everything else is a request, right or wrong, and gets an answer.
"""
import json
import os
import re
import sys

WORKFLOW = os.path.join(os.path.dirname(__file__), '..', '.github', 'workflows', 'build.yml')

# project_ref is a free-text input. It becomes `git clone --branch <ref>`, so it is held to what a
# git ref can contain and nothing else - no spaces, no quotes, no shell metacharacters.
REF = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._/-]{0,98}$')

# build_id is the other one, and it is optional. The page puts a nonce in it so that, after the
# reader has submitted the issue, the page can find the run this request produced instead of
# guessing at the newest one. It ends up in the workflow's run-name, which is a label and not a
# shell word - but it is still a string a stranger can choose, so it is held to the narrowest
# thing that can do the job.
BUILD_ID = re.compile(r'^[A-Za-z0-9][A-Za-z0-9-]{0,39}$')

FENCE = re.compile(r'```(?:json)?\s*(\{.*?\})\s*```', re.S)
BARE = re.compile(r'(\{.*\})', re.S)


def options(path):
    """The option list of every choice input in a workflow, without a YAML parser.

    Actions runners have PyYAML, but this runs before any install step and the file's shape is
    fixed and simple, so reading it directly keeps the job to one step with no dependency.
    """
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


def emit(pairs):
    """Write GITHUB_OUTPUT lines, with nothing in a value that could become another line.

    GITHUB_OUTPUT is line-based and a later assignment wins, so a newline inside a value injects an
    output - and `ok` is the one the workflow branches on. A crafted JSON key did exactly that here:
    {"x\nok=true\nz": 1} came back as a refusal followed by an injected ok=true, which would have
    turned a refusal into a build. Found by testing the refusal paths rather than the accepting one.

    So every value is flattened to one line and bounded, at the single point they all leave through,
    rather than at each message that builds one.
    """
    for key, value in pairs:
        flat = ' '.join(str(value).split())
        if len(flat) > 400:
            flat = flat[:397] + '...'
        print('%s=%s' % (key, flat))


def refuse(why, request=True):
    """Refuse, and say whether this was a build request at all.

    The two are different and the workflow needs both. A body with no JSON block in it is an
    ordinary issue - a bug report, a question - and must be answered with silence. A body that
    carries a request and gets it wrong must be answered with the reason, or the person who filed
    it is left watching a page that will never finish.
    """
    emit([('request', 'true' if request else 'false'), ('ok', 'false'), ('why', why)])
    return 0


def main():
    body = os.environ.get('ISSUE_BODY') or ''

    allowed = options(os.path.normpath(WORKFLOW))
    if not allowed:
        return refuse('Could not read the option lists out of build.yml.')

    m = FENCE.search(body) or BARE.search(body)
    if not m:
        return refuse('No JSON block in the issue body. This issue was not filed from the build page.',
                      request=False)
    try:
        req = json.loads(m.group(1))
    except ValueError as exc:
        return refuse('The JSON block does not parse: %s' % exc)
    if not isinstance(req, dict):
        return refuse('The JSON block is not an object.')

    wanted = sorted(allowed) + ['project_ref']
    out = []
    for key in wanted:
        if key not in req:
            return refuse('Missing: %s' % key)
        value = req[key]
        if not isinstance(value, str):
            return refuse('%s is not a string.' % key)
        value = value.strip()
        if key == 'project_ref':
            if not REF.match(value):
                return refuse('project_ref is not a plausible git ref: %r' % value)
        elif value not in allowed[key]:
            return refuse('%s=%r is not one of: %s' % (key, value, ', '.join(allowed[key])))
        out.append((key, value))

    # Optional, and absent is not an error: a request written by hand, or by an older copy of the
    # page, has no build_id and builds exactly as it did before. Present and malformed IS an error,
    # because the only thing that puts one there is the page, and a page that got it wrong should
    # hear so rather than have it quietly dropped.
    build_id = req.get('build_id', '')
    if not isinstance(build_id, str):
        return refuse('build_id is not a string.')
    build_id = build_id.strip()
    if build_id and not BUILD_ID.match(build_id):
        return refuse('build_id is not one this page would have written: %r' % build_id)
    out.append(('build_id', build_id))

    extra = sorted(set(req) - set(wanted) - {'build_id'})
    if extra:
        return refuse('Unexpected field(s): %s' % ', '.join(extra))

    emit([('request', 'true')] + out + [('ok', 'true')])
    return 0


if __name__ == '__main__':
    sys.exit(main())
