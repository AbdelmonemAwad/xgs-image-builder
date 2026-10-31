#!/usr/bin/env python3
#-
# SPDX-License-Identifier: BSD-2-Clause
#
"""The cases request-limits.py's decide() has to get right: the owner always, a stranger's driver
only as a release, one build at a time, three a day.
    python3 tools/test-request-limits.py"""
import importlib.util
import pathlib
import sys

spec = importlib.util.spec_from_file_location('limits', pathlib.Path(__file__).with_name('request-limits.py'))
limits = importlib.util.module_from_spec(spec)
spec.loader.exec_module(limits)
decide = limits.decide

CASES = [
    # (what, args, expected)
    ('the owner, a branch, busy and over the day', ('Owner', 'owner', 'main', False, [5], 9), ('ok', '')),
    ('a stranger, latest, nothing else', ('someone', 'owner', 'latest', False, [], 0), ('ok', '')),
    ('a stranger, a published release', ('someone', 'owner', 'v0.1.0-alpha.10.4', True, [], 2), ('ok', '')),
    ('a stranger, a branch', ('someone', 'owner', 'main', False, [], 0), ('ref', 'main')),
    ('a stranger, a commit', ('someone', 'owner', '2c198c3', False, [], 0), ('ref', '2c198c3')),
    ('a stranger with one still open', ('someone', 'owner', 'latest', False, [12, 9], 1), ('busy', '9')),
    ('a stranger, the third today is allowed', ('someone', 'owner', 'latest', False, [], 2), ('ok', '')),
    ('a stranger, a fourth today', ('someone', 'owner', 'latest', False, [], 3), ('limited', '3')),
    ('a wrong driver is said before a busy one', ('someone', 'owner', 'dev', False, [4], 5), ('ref', 'dev')),
]

bad = 0
for what, args, want in CASES:
    got = decide(*args)
    print('%s %s: %s' % ('ok  ' if got == want else 'FAIL', what, got))
    bad += got != want
print('%d of %d' % (len(CASES) - bad, len(CASES)))
sys.exit(1 if bad else 0)
