#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause
#
# The cases read-request.py has to get right, including the ones that found a bug.
#
# The injection cases are here because they were not hypothetical. Testing only the accepting path
# passed; testing the REFUSING paths found that a crafted JSON key -
# {"x\nok=true\nz": 1} - put a bare `ok=true` line into GITHUB_OUTPUT after the refusal, and a
# later assignment wins, so a refused request would have been built. The fix was to flatten every
# emitted value at the one point they all leave through. These stay so it cannot come back.
#
#     tools/test-read-request.sh
#
# Exit status is 0 when every case behaves, 1 otherwise.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="${HERE}/read-request.py"
pass=0
fail=0

# ok <name> <expected ok count> <issue body>
ok() {
    name=$1
    want=$2
    body=$3
    got=$(ISSUE_BODY="${body}" python3 "${SCRIPT}" | grep -c '^ok=true$')
    if [ "${got}" = "${want}" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL  %-26s wanted %s ok=true line(s), got %s\n' "${name}" "${want}" "${got}"
        ISSUE_BODY="${body}" python3 "${SCRIPT}" | sed 's/^/        /'
    fi
}

GOOD='"opnsense_version":"26.7","image_type":"serial","console_speed":"38400","serial_console":"yes","project_ref":"main"'

ok 'fenced, from the page'  1 "$(printf '```json\n{%s}\n```' "${GOOD}")"
ok 'bare json'              1 "{${GOOD}}"
ok 'dvd is a valid choice'  1 '{"opnsense_version":"26.7","image_type":"dvd","console_speed":"38400","serial_console":"yes","project_ref":"main"}'
ok 'a tag as the ref'       1 '{"opnsense_version":"26.1","image_type":"nano","console_speed":"115200","serial_console":"no","project_ref":"v1.2.3"}'

ok 'not filed from the page' 0 'hello, I would like an image'
ok 'malformed json'          0 '```json
{"opnsense_version": "26.7",}
```'
ok 'version not offered'     0 '{"opnsense_version":"25.1","image_type":"serial","console_speed":"38400","serial_console":"yes","project_ref":"main"}'
ok 'type not offered'        0 '{"opnsense_version":"26.7","image_type":"floppy","console_speed":"38400","serial_console":"yes","project_ref":"main"}'
ok 'missing a field'         0 '{"opnsense_version":"26.7","image_type":"serial","console_speed":"38400","serial_console":"yes"}'
ok 'an extra field'          0 "{${GOOD},\"evil\":\"1\"}"
ok 'a value is not a string' 0 '{"opnsense_version":26.7,"image_type":"serial","console_speed":"38400","serial_console":"yes","project_ref":"main"}'
ok 'json is not an object'   0 '```json
["26.7"]
```'

# project_ref is the only free text, and it becomes `git clone --branch <ref>`.
ok 'ref: command substitution' 0 '{"opnsense_version":"26.7","image_type":"serial","console_speed":"38400","serial_console":"yes","project_ref":"main$(id)"}'
ok 'ref: semicolon'            0 '{"opnsense_version":"26.7","image_type":"serial","console_speed":"38400","serial_console":"yes","project_ref":"main; rm -rf /"}'
ok 'ref: backtick and quote'   0 '{"opnsense_version":"26.7","image_type":"serial","console_speed":"38400","serial_console":"yes","project_ref":"a\"`id`"}'
ok 'ref: leading dash'         0 '{"opnsense_version":"26.7","image_type":"serial","console_speed":"38400","serial_console":"yes","project_ref":"--upload-pack=sh"}'
ok 'ref: empty'                0 '{"opnsense_version":"26.7","image_type":"serial","console_speed":"38400","serial_console":"yes","project_ref":""}'

# The two that found the bug.
ok 'output injection via key'   0 "{${GOOD},\"x\\nok=true\\nz\":\"1\"}"
ok 'output injection via value' 0 '{"opnsense_version":"26.7\nok=true","image_type":"serial","console_speed":"38400","serial_console":"yes","project_ref":"main"}'

# build_id is optional, and it reaches the workflow's run-name. A request without one builds as it
# always did; one with a malformed one is refused rather than quietly dropped, because the only
# thing that writes a build_id is the page.
ok 'build_id: absent'          1 "{${GOOD}}"
ok 'build_id: empty string'    1 "{${GOOD},\"build_id\":\"\"}"
ok 'build_id: the page shape'  1 "{${GOOD},\"build_id\":\"web-m1x9qk-4f20ab\"}"
ok 'build_id: expression'      0 "{${GOOD},\"build_id\":\"\${{ secrets.GITHUB_TOKEN }}\"}"
ok 'build_id: space'           0 "{${GOOD},\"build_id\":\"a b\"}"
ok 'build_id: quote'           0 "{${GOOD},\"build_id\":\"a\\\"b\"}"
ok 'build_id: leading dash'    0 "{${GOOD},\"build_id\":\"-x\"}"
ok 'build_id: too long'        0 "{${GOOD},\"build_id\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}"
ok 'build_id: not a string'    0 "{${GOOD},\"build_id\":7}"
ok 'build_id: newline'         0 "{${GOOD},\"build_id\":\"a\nok=true\"}"

# `request` tells an ordinary issue from a request that is wrong. The workflow answers the second
# and must stay silent on the first - that distinction is what keeps this off every bug report, and
# what makes a stranger's malformed request get a reply instead of nothing.
want_request() {
    name=$1; want=$2; body=$3
    got=$(ISSUE_BODY="${body}" python3 "${SCRIPT}" | sed -n 's/^request=//p')
    if [ "${got}" = "${want}" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL  %-26s wanted request=%s, got %s\n' "${name}" "${want}" "${got:-(nothing)}"
    fi
}
want_request 'request: prose only'      false 'The appliance will not boot after the update.'
want_request 'request: empty body'      false ''
want_request 'request: a good one'      true  "{${GOOD}}"
want_request 'request: bad value'       true  '{"opnsense_version":"9.9","image_type":"serial","console_speed":"38400","serial_console":"yes","project_ref":"main"}'
want_request 'request: missing field'   true  '{"image_type":"serial"}'
want_request 'request: broken json'     true  '{"opnsense_version": }'
want_request 'request: bad build_id'    true  "{${GOOD},\"build_id\":\"a b\"}"

# And nothing a refusal prints may become a second output line.
lines=$(ISSUE_BODY="{${GOOD},\"x\\nok=true\\nz\":\"1\"}" python3 "${SCRIPT}" | wc -l | tr -d ' ')
if [ "${lines}" = 3 ]; then
    pass=$((pass + 1))
else
    fail=$((fail + 1))
    printf 'FAIL  %-26s a refusal must print exactly 3 lines, printed %s\n' 'refusal line count' "${lines}"
fi

printf '%d passed, %d failed\n' "${pass}" "${fail}"
[ "${fail}" = 0 ]
