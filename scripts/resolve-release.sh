#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause
#
# Work out which upstream file to fetch, prove the release publishes it, and print its checksum.
#
# Runs on the Linux runner, before the FreeBSD guest starts, so that a dropdown combination the
# release does not publish fails here in a few seconds - naming what IS published - rather than
# forty minutes later inside a guest with a 404 for a download.
#
# IT DOES NOT ASSEMBLE A FILE NAME AND HOPE. The names could not be verified while this was
# written: the network policy in that environment denied the OPNsense mirrors, so any URL built
# here would have been a guess presented as a fact. So this reads the release's own checksum file -
# which lists exactly what that release published - and selects from it. If the combination is not
# in the list, the list is the error message.
#
# Usage: resolve-release.sh <version> <type>
# Prints three lines on success: URL, FILENAME, SHA256.

set -eu

VERSION=$1
TYPE=$2

: "${MIRROR:=https://mirror.ams1.nl.leaseweb.net/opnsense}"
BASE="${MIRROR}/releases/${VERSION}"

# The checksum file is the index. Its name has not been constant across releases, so try the forms
# that have been used rather than hard-coding one.
SUMS=""
for candidate in \
    "OPNsense-${VERSION}-checksums-amd64.sha256" \
    "OPNsense-${VERSION}-checksums-amd64.txt" \
    SHA256SUMS \
    MD5SUMS
do
    if curl -fsSL --max-time 60 -o /tmp/sums "${BASE}/${candidate}"; then
        SUMS=${candidate}
        break
    fi
done

if [ -z "${SUMS}" ]; then
    echo "No checksum file under ${BASE}." >&2
    echo "Either ${VERSION} is not a published release, or this mirror does not carry it." >&2
    echo "Set MIRROR to a different one and run again." >&2
    exit 1
fi

# An installer ISO for dvd, a disk image for the rest. Both arrive bzip2'd.
case "${TYPE}" in
dvd) WANT="OPNsense-${VERSION}-${TYPE}-amd64.iso.bz2" ;;
*)   WANT="OPNsense-${VERSION}-${TYPE}-amd64.img.bz2" ;;
esac

# Checksum files have been written both ways round - "<sum>  <file>" and
# "SHA256 (<file>) = <sum>" - so match the name anywhere on the line and take the hex field.
LINE=$(grep -F "${WANT}" /tmp/sums || true)
if [ -z "${LINE}" ]; then
    echo "${VERSION} does not publish ${WANT}." >&2
    echo "What ${VERSION} publishes for amd64:" >&2
    grep -oE 'OPNsense-[0-9.]+-[a-z]+-amd64\.(iso|img)\.bz2' /tmp/sums | sort -u | sed 's/^/  /' >&2
    exit 1
fi

SHA=$(printf '%s\n' "${LINE}" | grep -oE '[0-9a-fA-F]{64}' | head -1)
if [ -z "${SHA}" ]; then
    # An MD5-only release. Refuse: this image gets written to a firewall's boot device, and a
    # download nothing can verify is not something to put there.
    echo "Found ${WANT} but no SHA-256 for it in ${SUMS}." >&2
    echo "Refusing to build from a download this cannot verify." >&2
    exit 1
fi

echo "${BASE}/${WANT}"
echo "${WANT}"
echo "${SHA}"
