#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause
#
# Clone every repository components.list names into <dest>/<name>, each at the ref the list gives,
# and record which commit came: one line per component in <dest>/STAMPS, also printed.
#
# The same rule as fetch-project.sh, and for the same reason: nothing here is a copy of those
# projects. A vendored second copy goes stale and nobody notices.
#
# Usage: fetch-components.sh <list> <dest>

set -eu

LIST=$1
DEST=$2
HERE=$(cd "$(dirname "$0")" && pwd)

rm -rf "${DEST}"
mkdir -p "${DEST}"
: > "${DEST}/STAMPS"

grep -v '^[[:space:]]*#' "${LIST}" | grep -v '^[[:space:]]*$' | while read -r name url ref; do
    # The name becomes a directory in the image and a word in a log line; keep it to the shape
    # every name in the list has, so a typo cannot become a path.
    case ${name} in
    *[!a-z0-9-]*|'') echo "components.list: '${name}' is not a component name" >&2; exit 1 ;;
    esac
    case ${url} in
    https://github.com/*) ;;
    *) echo "components.list: ${name}: '${url}' is not a GitHub repository URL" >&2; exit 1 ;;
    esac
    stamp=$(PROJECT_URL=${url} sh "${HERE}/fetch-project.sh" "${ref:-main}" "${DEST}/${name}")
    rm -rf "${DEST}/${name}/.git"
    # The commit, inside the tree, for its installer: with .git gone this is the only place it can
    # read what it is installing, and it records that as the version its daily self-update moves
    # forward from. Without it the first release would be taken even when it is older than this.
    printf '%s\n' "${stamp}" > "${DEST}/${name}/.source-commit"
    printf '%s %s\n' "${name}" "${stamp}" | tee -a "${DEST}/STAMPS"
done
