#!/usr/bin/env python3
#-
# SPDX-License-Identifier: BSD-2-Clause
#
"""Whether a valid build request may start, now that anyone may ask (2026-11-01).

Builds run for every account since then - npuforge.org's build page files the request, this
repository builds it - and three limits keep that fair to everyone and to the project's own release
builds, which share the account's runners:

  * the driver is `latest` or one of os-xgs-npu's published releases - a branch or a commit is the
    owner's to build, not a stranger's;
  * one build at a time for each account - an earlier request still open is still building, since
    build.yml's answer job closes each one when its run ends;
  * three builds a day for each account - requests of the last 24 hours that were started.

The owner's requests skip all three. read-request.py has already held every value to its pattern;
this only decides. Reads AUTHOR, OWNER, ISSUE, REF and REPO from the environment and asks GitHub
through `gh` (GH_TOKEN). Writes `verdict=<ok|ref|busy|limited>` and `detail=<number or ref>` for
GITHUB_OUTPUT on stdout, and exits 0 whatever it decides: the workflow answers the request either way.
"""
import datetime
import json
import os
import re
import subprocess
import sys

DAILY = 3
DRIVER = 'AbdelmonemAwad/os-xgs-npu'
REQUEST = re.compile(r'"build_id"\s*:')
STARTED = '<!-- xgs-result: started -->'


def decide(author, owner, ref, ref_released, open_others, started_today):
    """The verdict and its detail, from what GitHub said. Kept apart from GitHub so it is tested."""
    if author.lower() == owner.lower():
        return 'ok', ''
    if ref != 'latest' and not ref_released:
        return 'ref', ref
    if open_others:
        return 'busy', str(min(open_others))
    if started_today >= DAILY:
        return 'limited', str(started_today)
    return 'ok', ''


def gh(*args):
    out = subprocess.run(['gh'] + list(args), capture_output=True, text=True)
    return out.returncode, out.stdout


def main():
    try:
        verdict, detail = check()
    except Exception as e:  # anything GitHub or the environment did: answered, not a failed run
        print('the limits could not be checked: %s' % e, file=sys.stderr)
        verdict, detail = 'error', ''
    # one line each, and nothing in them but what decide() made from closed sets and numbers
    print('verdict=%s' % verdict)
    print('detail=%s' % re.sub(r'[^A-Za-z0-9._/-]', '', detail))
    return 0


def check():
    author, owner = os.environ['AUTHOR'], os.environ['OWNER']
    issue, ref, repo = int(os.environ['ISSUE']), os.environ['REF'], os.environ['REPO']
    if author.lower() == owner.lower():
        verdict, detail = 'ok', ''
    else:
        rc, _ = gh('api', 'repos/%s/releases/tags/%s' % (DRIVER, ref)) if ref != 'latest' else (0, '')
        released = rc == 0
        rc, text = gh('issue', 'list', '-R', repo, '--author', author, '--state', 'all', '--limit', '50',
                      '--json', 'number,state,createdAt,body')
        mine = [i for i in (json.loads(text) if rc == 0 else []) if i['number'] != issue and REQUEST.search(i['body'] or '')]
        open_others = [i['number'] for i in mine if i['state'] == 'OPEN']
        since = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=24)
        started = 0
        for i in mine:
            made = datetime.datetime.fromisoformat(i['createdAt'].replace('Z', '+00:00'))
            if made < since:
                continue
            rc, text = gh('api', 'repos/%s/issues/%d/comments' % (repo, i['number']), '--jq', '.[].body')
            if rc == 0 and STARTED in text:
                started += 1
        verdict, detail = decide(author, owner, ref, released, open_others, started)
    return verdict, detail


if __name__ == '__main__':
    sys.exit(main())
