#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause
#
# Put the project into an OPNsense disk image, with the kernel sources it will need, and set the
# console. THIS RUNS INSIDE A FreeBSD GUEST.
#
# WHY A GUEST AND NOT THE UBUNTU RUNNER. An OPNsense image is UFS. Linux's UFS write support is not
# something to put a firewall's boot device on the other side of. In a FreeBSD guest, mdconfig,
# gpart, growfs, fsck_ffs and mount are the native tools for the filesystem they were written for.
#
# IT MAKES NO HARDWARE DECISION, and that is the design rather than a shortcut. It does not run the
# project's install.sh, because install.sh reads the board's assembly number out of SMBIOS and
# installs only that family's pieces - a decision that cannot be made in a virtual machine with no
# appliance under it. CONTRIBUTING.md fixes this: all families in one image, selected at run time.
# So the whole project goes in, and a first-boot hook runs install.sh on the real machine where both
# board maps are readable. See docs/board-maps.md.
#
# AND IT CARRIES THE KERNEL SOURCES, which is the part that makes the image work rather than merely
# boot. install.sh builds the module through kernel-follow.sh at install time, and that needs the
# running kernel's sources. On an XGS 3300 the WAN is one of the coprocessor's own front ports, so
# there is no network until the module exists - and the module cannot be built without the sources.
# The project's own kernel-sources/README.md names that circle and says what breaks it: a tarball
# carried beside the installer. install.sh copies anything in <tree>/kernel-sources/ into
# /usr/local/share/os-xgs-npu/kernel-sources/, and fetch-sources.sh prefers it over the network.
# So this fetches the tarball for THIS IMAGE'S kernel and puts it there.
#
# NO PREBUILT MODULE. A module built against a different kernel in the same branch loads without
# complaining and then reads structures at the wrong offsets. Sources only.
#
# Usage: inject.sh <image> <console_speed> <serial_console yes|no> <project dir> <stamp>

set -eu

IMG=$1
SPEED=$2
SERIAL=$3
PROJECT=$4
STAMP=$5

MNT=/mnt/target
MD=""
# Room for the kernel source tarball plus the project plus slack. The tarball is the big one: the
# project's own notes put an extracted sys/ tree at about 350 MB.
NEED_MB=900

say() { echo "==> $*"; }

detach() {
    [ -n "${MD}" ] || return 0
    umount "${MNT}" 2>/dev/null || true
    mdconfig -d -u "${MD}" 2>/dev/null || true
    MD=""
}
trap 'set +e; detach' EXIT INT TERM

attach() {
    MD=$(mdconfig -a -t vnode -f "${IMG}")
    PART=$(gpart show -p "${MD}" | awk '$4 == "freebsd-ufs" { print $3; exit }')
    if [ -z "${PART}" ]; then
        say "no freebsd-ufs partition in ${IMG} - this is not an OPNsense disk image"
        gpart show -p "${MD}" >&2
        exit 1
    fi
    # The partition index, for gpart resize. Taken from the provider name rather than assumed: the
    # layout has not been constant across releases and "p2" is a guess that fails as a bad mount.
    PIDX=${PART##*p}
}

mkdir -p "${MNT}"

# ------------------------------------------------------------------ read the kernel's own commit

attach
say "attached ${IMG} as /dev/${MD}, root on /dev/${PART}"
mount -o ro "/dev/${PART}" "${MNT}"

# The method is the project's own, from fetch-sources.sh: a kernel that is not running still names
# the commit it was built from, inside the binary.
KERNEL="${MNT}/boot/kernel/kernel"
if [ ! -f "${KERNEL}" ]; then
    say "no /boot/kernel/kernel in the image - cannot tell which sources it needs"
    exit 1
fi
KVER=$(strings -a "${KERNEL}" | grep -m1 '^FreeBSD 1.*stable/' || true)
if [ -z "${KVER}" ]; then
    say "could not read a kernel version string out of the image's kernel"
    exit 1
fi
say "image kernel: ${KVER}"

# stable/26.7-n283949-083dc7025377 -> 083dc7025377
SHA=$(printf '%s\n' "${KVER}" | sed -n 's/.*-n[0-9]*-\([0-9a-f][0-9a-f]*\).*/\1/p')
if [ -z "${SHA}" ]; then
    say "the version string names no commit - nothing to fetch sources for"
    exit 1
fi
say "kernel sources wanted: opnsense/src at ${SHA}"

umount "${MNT}"
detach

# ------------------------------------------------------------------ fetch those sources

# Deliberately NOT inside ${PROJECT}/kernel-sources, which is where the project's own
# kernel-sources/README.md says to drop it for a hand install. install.sh copies from there into
# /usr/local/share/os-xgs-npu/kernel-sources with `install -m 0644` - a copy, not a move - so a
# tarball placed in the tree would end up in the image TWICE, about 300 MB each, and the image
# would have to be grown for both. fetch-sources.sh reads that pool directly, so this writes
# straight into the pool and leaves the tree without one. install.sh then finds the pool already
# populated, copies nothing, and prints no warning, because the check it makes is on the pool.
TARBALL="src-${SHA}.tar.gz"
say "fetching https://codeload.github.com/opnsense/src/tar.gz/${SHA}"
if ! fetch -q -o "${TARBALL}" "https://codeload.github.com/opnsense/src/tar.gz/${SHA}"; then
    say "could not fetch the kernel sources for ${SHA}"
    say "Without them the appliance cannot build the module on first boot, and on an XGS 3300"
    say "it has no network to fetch them with either - see kernel-sources/README.md in the"
    say "project. Refusing to produce an image that cannot finish installing itself."
    exit 1
fi
TAR_MB=$(( $(stat -f %z "${TARBALL}") / 1024 / 1024 ))
say "kernel sources: ${TAR_MB} MB"

# ------------------------------------------------------------------ make room, then write

PROJ_MB=$(( $(du -sk "${PROJECT}" | awk '{print $1}') / 1024 ))
WANT_MB=$(( PROJ_MB + TAR_MB + 128 ))
[ "${WANT_MB}" -lt "${NEED_MB}" ] && WANT_MB=${NEED_MB}
say "project ${PROJ_MB} MB + sources ${TAR_MB} MB + slack = ${WANT_MB} MB wanted"

attach
mount "/dev/${PART}" "${MNT}"
FREE_MB=$(df -m "${MNT}" | awk 'NR==2 {print $4}')
say "image has ${FREE_MB} MB free, this needs about ${WANT_MB} MB"

if [ "${FREE_MB}" -lt "${WANT_MB}" ]; then
    GROW_MB=$(( WANT_MB - FREE_MB + 256 ))
    say "growing the image by ${GROW_MB} MB"
    umount "${MNT}"
    detach

    # Grow the file, then the table, then the partition, then the filesystem. gpart recover is not
    # optional: growing the file leaves the secondary GPT header in the middle of the device, and
    # gpart refuses to resize until it has been moved to the new end.
    truncate -s "+${GROW_MB}M" "${IMG}"
    attach
    gpart recover "${MD}"
    gpart resize -i "${PIDX}" "${MD}"
    growfs -y "/dev/${PART}"
    mount "/dev/${PART}" "${MNT}"
    FREE_MB=$(df -m "${MNT}" | awk 'NR==2 {print $4}')
    say "now ${FREE_MB} MB free"
    if [ "${FREE_MB}" -lt "${WANT_MB}" ]; then
        say "still short after growing - refusing rather than writing a partial tree"
        exit 1
    fi
fi

# ------------------------------------------------------------------ the project, whole

if [ ! -d "${MNT}/usr/local" ]; then
    say "no /usr/local in the mounted image - this is not an OPNsense root"
    exit 1
fi

SHARE="${MNT}/usr/local/share/os-xgs-npu"
mkdir -p "${SHARE}/source"
# cp -a rather than a tar pipe: one filesystem to another, and it keeps the modes install.sh's own
# `install -m` lines expect to find.
cp -a "${PROJECT}/." "${SHARE}/source/"
rm -rf "${SHARE}/source/.git"

# Which commit of the project is on this appliance - the first question anyone debugging one asks.
printf '%s\n' "${STAMP}" > "${SHARE}/source/.image-build"
say "project installed under /usr/local/share/os-xgs-npu/source"

# And the kernel sources, straight into the pool fetch-sources.sh reads.
mkdir -p "${SHARE}/kernel-sources"
cp "${TARBALL}" "${SHARE}/kernel-sources/"
say "kernel sources placed in /usr/local/share/os-xgs-npu/kernel-sources/${TARBALL}"

# ------------------------------------------------------------------ the console

# loader.conf.local, not loader.conf: the loader reads it afterwards so these win, and OPNsense
# rewrites loader.conf on its own account.
#
# This is the setting that costs an afternoon when it is wrong. These appliances have no screen,
# and the project records the XGS 3300's console as 38400 under the vendor firmware and 115200
# under OPNsense, on the same port.
{
    echo "# Written by xgs-image-builder. The appliance has no screen; see its README."
    echo "comconsole_speed=\"${SPEED}\""
    if [ "${SERIAL}" = yes ]; then
        echo "console=\"comconsole\""
    else
        echo "console=\"comconsole,vidconsole\""
    fi
    echo "boot_multicons=\"YES\""
    echo "boot_serial=\"YES\""
} >> "${MNT}/boot/loader.conf.local"

# And then getty, but ONLY IF IT PINS A SPEED - which the stock line does not, and assuming it did
# was a bug in the first version of this script.
#
# FreeBSD's own /etc/ttys ships `ttyu0 "/usr/libexec/getty 3wire"`, and in gettytab the bare 3wire
# entry is `:np:nc:sp#0:`. Speed 0 means do not change the port speed, so getty inherits whatever
# the kernel console is already running at - which is what comconsole_speed above just set. In that
# case the loader setting is the whole job and touching this file would be noise.
#
# The pinned forms - std.115200, 3wire.38400 - do override it, and a distribution is free to ship
# one. So this looks, acts only on the pinned case, and SAYS WHICH IT FOUND. A silent no-op here is
# the shape of fault that leaves an unreadable login prompt after a readable boot.
TTYS="${MNT}/etc/ttys"
if [ ! -f "${TTYS}" ]; then
    say "console: ${SPEED} baud in the loader; no /etc/ttys in this image"
else
    CUR=$(grep -E '^ttyu0[[:space:]]' "${TTYS}" || true)
    case "${CUR}" in
    '')
        say "console: ${SPEED} baud in the loader; no ttyu0 line in /etc/ttys" ;;
    *std.[0-9]*|*3wire.[0-9]*)
        sed -i '' -E "/^ttyu0[[:space:]]/s/(std|3wire)\.[0-9]+/\1.${SPEED}/" "${TTYS}"
        say "console: ${SPEED} baud in the loader and in /etc/ttys, which pinned a speed"
        grep -E '^ttyu0[[:space:]]' "${TTYS}" ;;
    *)
        say "console: ${SPEED} baud in the loader; /etc/ttys uses an unpinned getty entry and follows it" ;;
    esac
fi

# ------------------------------------------------------------------ first boot

# install.sh has to run where SMBIOS is readable. It runs once, logs, and leaves a marker so a
# reboot does not repeat it. Every failure exits 0: a firewall that boots without the coprocessor
# is better than one that does not boot, which is the rule 08-octep already follows.
#
# The `start` level is used because it is one the appliance actually calls. The project learned
# that the expensive way - a hook at a level nobody calls "looks like a guarantee and it is a file".
HOOKDIR="${MNT}/usr/local/etc/rc.syshook.d/start"
mkdir -p "${HOOKDIR}"
cat > "${HOOKDIR}/00-os-xgs-npu-firstboot" <<'HOOK'
#!/bin/sh
#-
# Install os-xgs-npu on first boot, from the sources this image carries.
#
# NOT TESTED ON AN APPLIANCE. If this does nothing, the tree is under
# /usr/local/share/os-xgs-npu/source and install/install.sh can be run by hand as root.

SRC=/usr/local/share/os-xgs-npu/source
MARKER=/usr/local/share/os-xgs-npu/.installed
LOG=/var/log/os-xgs-npu-install.log

log() { /usr/bin/logger -t os-xgs-npu -p daemon.notice "$1"; }

[ -f "${MARKER}" ] && exit 0
[ -d "${SRC}" ] || { log "no ${SRC} - nothing to install"; exit 0; }

log "installing from ${SRC}; this builds the kernel module and takes a few minutes"

# install.sh refuses a board this project has not run on, and that is the behaviour wanted here:
# an unknown appliance gets nothing rather than another board's pieces.
if /bin/sh "${SRC}/install/install.sh" > "${LOG}" 2>&1; then
    date > "${MARKER}"
    log "installed - see ${LOG}"
else
    log "install.sh refused or failed; see ${LOG}. Carrying on so the firewall still boots"
fi
exit 0
HOOK
chmod 0755 "${HOOKDIR}/00-os-xgs-npu-firstboot"
say "first-boot hook installed"

# ------------------------------------------------------------------ close it cleanly

df -m "${MNT}" | awk 'NR==2 {printf "==> %s MB free left in the image\n", $4}'
sync
umount "${MNT}"
fsck_ffs -y "/dev/${PART}" >/dev/null 2>&1 || true
detach
say "done: ${IMG}"
