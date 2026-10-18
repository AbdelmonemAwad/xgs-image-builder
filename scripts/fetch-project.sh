#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause
#
# Clone os-xgs-npu at the ref the dropdown chose, into ./project.
#
# Nothing here is a copy of that project. A vendored second copy goes stale and nobody notices,
# which is the same reason the project itself does not vendor the kernel sources it builds against.
#
# Usage: fetch-project.sh <ref> [destination]
# Prints one line: the commit, its date and its subject - with the release's tag between the date
# and the subject when what was fetched is a release, which is where the appliance's installer
# looks for it (install/install.sh reads the third field of .image-build).
#
# <ref> `latest` is the project's newest release, the one every appliance's Updates page offers -
# so an image starts on the version an update would bring, not on whatever was merged last.

set -eu

REF=$1
DEST=${2:-project}
: "${PROJECT_URL:=https://github.com/AbdelmonemAwad/os-xgs-npu}"

rm -rf "${DEST}"

# GitHub answers /releases/latest with a redirect to the release's tag, which needs no API and no
# token. A project with no release at all - a fork of one that has none - gets main, and is told.
if [ "${REF}" = latest ]; then
    TAG=$(curl -fsSI "${PROJECT_URL}/releases/latest" 2>/dev/null | tr -d '\r' \
        | sed -n 's#^[Ll]ocation: .*/releases/tag/\(v[0-9][0-9A-Za-z.-]*\)$#\1#p' | head -1)
    if [ -n "${TAG}" ]; then
        REF=${TAG}
    else
        echo "fetch-project: the project has no release; installing main" >&2
        REF=main
    fi
fi

# --branch takes a tag or a branch. A bare commit does not work with --depth 1 on clone, so that
# case fetches it explicitly rather than falling back to a full clone.
if ! git clone --quiet --depth 1 --branch "${REF}" "${PROJECT_URL}" "${DEST}" 2>/dev/null; then
    git init -q "${DEST}"
    git -C "${DEST}" remote add origin "${PROJECT_URL}"
    git -C "${DEST}" fetch -q --depth 1 origin "${REF}"
    git -C "${DEST}" checkout -q FETCH_HEAD
fi

# One printable line, and bounded. The caller writes this to GITHUB_OUTPUT, which is line-based
# and where a later assignment wins - the same shape of fault this repository already fixed once in
# tools/read-request.py, found there by testing the refusal path rather than the accepting one. A
# commit subject is one line by git's definition, but "by definition" is not the same as checked.
case ${REF} in
v[0-9]*.[0-9]*.[0-9]*) FORMAT="%H %cI ${REF} %s" ;;
*) FORMAT='%H %cI %s' ;;
esac
git -C "${DEST}" --no-pager log -1 --format="${FORMAT}" \
    | tr '\n\r' '  ' \
    | tr -d '\000-\010\013-\037\177' \
    | cut -c1-200
