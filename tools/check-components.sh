#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause
#
# Every repository in components.list, as it is on its ref today, still carries what the image's
# first-boot hook calls in it.
#
# This repository holds no copy of them: each build takes each one's ref fresh, so every change a
# repository makes reaches the next image without anything being done here. That is the point, and
# it has a cost - a repository that moves or renames an installer breaks the image, and nothing on
# its side would say so. This is the check on this side. It fetches the components the way a build
# does and looks for each entry point the hook in scripts/inject.sh names; it runs on every change
# here and on a schedule, so a change made over there is caught here within a day.
#
#   tools/check-components.sh [components.list]
set -eu
LIST=${1:-components.list}
HERE=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

sh "${HERE}/scripts/fetch-components.sh" "${LIST}" "${W}/c" > /dev/null

bad=0
need() {
    if [ -f "${W}/c/$1" ]; then
        echo "ok    $1"
    else
        echo "MISSING $1 - the first-boot hook calls it"
        bad=1
    fi
}
# The entry points, as scripts/inject.sh's first-boot hook calls them.
need opnsense-arabic/install.sh
need opnsense-rtl/install.sh
for c in os-netreport os-linkhealth os-fanctl os-frontpanel; do
    need "${c}/install/install.sh"
done
need os-fanctl/install/enable.sh
need os-frontpanel/install/enable.sh

echo
sed 's/^/  /' "${W}/c/STAMPS" | cut -c1-100
exit ${bad}
