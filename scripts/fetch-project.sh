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
# Prints one line: the commit, its date and its subject.

set -eu

REF=$1
DEST=${2:-project}
: "${PROJECT_URL:=https://github.com/AbdelmonemAwad/os-xgs-npu}"

rm -rf "${DEST}"

# --branch takes a tag or a branch. A bare commit does not work with --depth 1 on clone, so that
# case fetches it explicitly rather than falling back to a full clone.
if ! git clone --quiet --depth 1 --branch "${REF}" "${PROJECT_URL}" "${DEST}" 2>/dev/null; then
    git init -q "${DEST}"
    git -C "${DEST}" remote add origin "${PROJECT_URL}"
    git -C "${DEST}" fetch -q --depth 1 origin "${REF}"
    git -C "${DEST}" checkout -q FETCH_HEAD
fi

git -C "${DEST}" --no-pager log -1 --format='%H %cI %s'
