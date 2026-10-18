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
# AND THE COMPONENTS: the Arabic translation, the right-to-left layout, the XGS Silicon theme and the
# four plugins, each fetched from its own repository by fetch-components.sh, and the package files of
# lcdproc, which the front panel plugin needs and which is fetched here, for this image, because on
# an XGS 3300 there is no network at first boot until the driver exists. All of it is installed by
# the first-boot hook at the end of this file, in an order that matters; the hook says why.
#
# The front panel plugin, and the LCDproc it needs, go in only when the build was told the
# appliance has a front panel - the last argument, the build page's "Front panel".
#
# Usage: inject.sh <image> <console_speed> <serial_console yes|no> <project dir> <stamp> [<components dir> [<front panel yes|no>]]

set -eu

IMG=$1
SPEED=$2
SERIAL=$3
PROJECT=$4
STAMP=$5
COMPONENTS=${6:-}
FRONT_PANEL=${7:-no}

# The speed goes into the loader, config.xml and /boot.config; a value none of them can use is
# refused here rather than written into three files.
case ${SPEED} in
9600|19200|38400|57600|115200) ;;
*) echo "inject.sh: '${SPEED}' is not a serial console speed" >&2; exit 1 ;;
esac
case ${SERIAL} in
yes|no) ;;
*) echo "inject.sh: serial_console is '${SERIAL}', not yes or no" >&2; exit 1 ;;
esac

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
COMP_MB=0
[ -n "${COMPONENTS}" ] && COMP_MB=$(( $(du -sk "${COMPONENTS}" | awk '{print $1}') / 1024 ))
# lcdproc and what it depends on are a few megabytes; 32 covers them with room.
WANT_MB=$(( PROJ_MB + COMP_MB + 32 + TAR_MB + 128 ))
[ "${WANT_MB}" -lt "${NEED_MB}" ] && WANT_MB=${NEED_MB}
say "project ${PROJ_MB} MB + components ${COMP_MB} MB + sources ${TAR_MB} MB + slack = ${WANT_MB} MB wanted"

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

# ------------------------------------------------------------------ the components

IMGSHARE="${MNT}/usr/local/share/xgs-image"
if [ -n "${COMPONENTS}" ]; then
    mkdir -p "${IMGSHARE}/components"
    cp -a "${COMPONENTS}/." "${IMGSHARE}/components/"
    if [ "${FRONT_PANEL}" != yes ]; then
        rm -rf "${IMGSHARE}/components/os-frontpanel"
        say "no front panel asked for: the front panel plugin is left out"
    fi
    say "components installed under /usr/local/share/xgs-image/components:"
    sed 's/^/      /' "${IMGSHARE}/components/STAMPS" | cut -c1-110
fi

# ------------------------------------------------------------------ the packages they need

# lcdproc, which the front panel plugin refuses to install without, and what it depends on. Fetched
# from the OPNsense repository THIS IMAGE is set up for, for THIS IMAGE's ABI - read off its own
# /usr/bin/uname - so the files are the ones its own pkg would have fetched. At first boot `pkg add`
# installs lcdproc from them and takes any dependency the image does not already have from the same
# directory. Installed that way it is a registered package, so firmware updates update it like any
# other from then on.
#
# The guest's own pkg does the fetching, pointed at a scratch database and at a copy of the image's
# repository file whose fingerprints path is moved into the mounted image: nothing is written into
# the image's own package database, and the signatures are checked against the image's own keys.
fetch_packages() {
    pkgtmp=$(mktemp -d /tmp/xib-pkg.XXXXXX)
    mkdir -p "${pkgtmp}/repos" "${pkgtmp}/db" "${pkgtmp}/cache"
    conf="${MNT}/usr/local/etc/pkg/repos/OPNsense.conf"
    [ -f "${conf}" ] || conf="${conf}.sample"
    if [ ! -f "${conf}" ]; then
        say "no OPNsense repository configuration in the image"
        return 1
    fi
    sed "s|\"/usr/local/etc/pkg/fingerprints|\"${MNT}/usr/local/etc/pkg/fingerprints|" "${conf}" \
        > "${pkgtmp}/repos/OPNsense.conf"
    if ! pkg -N > /dev/null 2>&1; then
        env ASSUME_ALWAYS_YES=yes pkg bootstrap -f > /dev/null
    fi
    rc=0
    # IP_VERSION=4: pkg.opnsense.org answers on IPv6 too, and a machine with an IPv6 route but no
    # IPv6 reach made pkg fail every request with "Network is unreachable" and sit in its retries
    # rather than fall back (measured on an XGS 136, where fetch(1) to an IPv4-only host worked).
    # A GitHub runner has no IPv6 at all. IPv4 reaches the repository from both.
    pkg -o ABI_FILE="${MNT}/usr/bin/uname" -o REPOS_DIR="${pkgtmp}/repos" \
        -o PKG_DBDIR="${pkgtmp}/db" -o PKG_CACHEDIR="${pkgtmp}/cache" \
        -o IGNORE_OSVERSION=yes -o ASSUME_ALWAYS_YES=yes -o IP_VERSION=4 \
        fetch -y -d -o "$1" lcdproc || rc=$?
    rm -rf "${pkgtmp}"
    return ${rc}
}
if [ -n "${COMPONENTS}" ] && [ "${FRONT_PANEL}" = yes ] && [ -d "${COMPONENTS}/os-frontpanel" ]; then
    mkdir -p "${IMGSHARE}/packages"
    if ! fetch_packages "${IMGSHARE}/packages"; then
        say "could not fetch lcdproc for this image. The front panel plugin cannot install without"
        say "it, and on an XGS 3300 there is no network at first boot to fetch it then. Refusing"
        say "to produce an image that cannot finish installing itself."
        exit 1
    fi
    say "packages carried for first boot: $(ls "${IMGSHARE}/packages/All" | tr '\n' ' ')"
fi

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

# And OPNsense's own configuration, which is the one that decides after the loader. At every boot
# OPNsense rewrites /etc/ttys - the getty that prints the login prompt - and /boot/loader.conf and
# /boot.config from the serial speed and the console choice in config.xml, and the serial image
# ships <serialspeed>115200</serialspeed>. With only the loader set, an image built for 38400 booted
# readably and then printed its login prompt at 115200: garbage on a 38400 terminal, seen on an
# appliance on 2026-10-16. QEMU never showed it, because its serial port has no speed.
#
# /usr/local/etc/config.xml is the factory default; opnsense-importer copies it to /conf/config.xml
# on a first boot, and the installer carries that to the disk. An image carries no /conf/config.xml
# today; one that did gets the same edit. A screen as well as the serial port (serial_console=no) is
# the secondary console, or OPNsense turns the screen's getty off and the screen has no login.
set_console_config() {
    cfg=$1
    for key in serialspeed primaryconsole secondaryconsole; do
        case ${key} in
        serialspeed) val=${SPEED} ;;
        primaryconsole) val=serial ;;
        secondaryconsole) [ "${SERIAL}" = yes ] && val= || val=video ;;
        esac
        if grep -q "<${key}>" "${cfg}"; then
            if [ -n "${val}" ]; then
                sed -i '' -E "s|<${key}>[^<]*</${key}>|<${key}>${val}</${key}>|" "${cfg}"
            else
                sed -i '' -E "/<${key}>[^<]*<\/${key}>/d" "${cfg}"
            fi
        elif [ -n "${val}" ]; then
            # after the first <system>, where the serial image keeps the other two
            awk -v line="    <${key}>${val}</${key}>" \
                '{ print } !done && /^[[:space:]]*<system>[[:space:]]*$/ { print line; done = 1 }' \
                "${cfg}" > "${cfg}.new" && mv "${cfg}.new" "${cfg}"
        fi
    done
    # Checked, not assumed: one serialspeed, at this speed, or the image is not built.
    if [ "$(grep -c "<serialspeed>${SPEED}</serialspeed>" "${cfg}")" != 1 ] ||
       [ "$(grep -c '<serialspeed>' "${cfg}")" != 1 ]; then
        say "console: ${cfg#${MNT}} does not carry serialspeed ${SPEED} after the edit"
        grep -n -E '<(serialspeed|primaryconsole|secondaryconsole)>' "${cfg}" >&2
        exit 1
    fi
    say "console: ${SPEED} baud in ${cfg#${MNT}}: $(grep -o -E '<(serialspeed|primaryconsole|secondaryconsole)>[^<]*' "${cfg}" | tr -d '<' | tr '>\n' '= ')"
}
for CFG in "${MNT}/usr/local/etc/config.xml" "${MNT}/conf/config.xml"; do
    [ -f "${CFG}" ] && set_console_config "${CFG}"
done
[ -f "${MNT}/usr/local/etc/config.xml" ] ||
    say "console: no /usr/local/etc/config.xml in this image - OPNsense will choose the speed itself"

# The boot blocks read /boot.config before the loader exists, on a machine that boots by BIOS, and
# the serial image ships -S115200. Written as OPNsense writes it from the same settings, so the
# first boot and every later one print at the same speed from the first line.
if [ "${SERIAL}" = yes ]; then
    echo "-S${SPEED} -h" > "${MNT}/boot.config"
else
    echo "-S${SPEED} -h -D" > "${MNT}/boot.config"
fi
say "console: /boot.config is $(cat "${MNT}/boot.config")"

# ------------------------------------------------------------------ first boot

# Everything is installed where SMBIOS is readable - on the machine itself, at its first boot - by
# one hook that does it in order, once per piece, and leaves a mark per piece so that a reboot does
# not repeat what is done and does retry what failed. Every failure exits 0: a firewall that boots
# without one of these is better than one that does not boot, which is the rule 08-octep follows.
#
# The `start` level is used because it is one the appliance actually calls. The project learned
# that the expensive way - a hook at a level nobody calls "looks like a guarantee and it is a file".
HOOKDIR="${MNT}/usr/local/etc/rc.syshook.d/start"
mkdir -p "${HOOKDIR}"
cat > "${HOOKDIR}/00-xgs-image-firstboot" <<'HOOK'
#!/bin/sh
#-
# Install what this image carries, on its first boot. NOT TESTED ON AN APPLIANCE.
#
# THE ORDER, and why each step is where it is:
#
#   1. os-xgs-npu       the coprocessor driver, built here from the sources this image carries.
#                       First, because on an XGS 3300 the WAN is one of the coprocessor's own ports:
#                       nothing has a network until the driver exists.
#   2. lcdproc          from the package files this image carries - there only when the image was
#                       built with a front panel. The front panel plugin refuses to install without
#                       LCDd, and there may be no network to fetch it with.
#   3. opnsense-arabic  before the plugins. Three of them add their own Arabic strings to the
#                       catalog it installs and skip a language whose catalog is not there, and
#                       its installer writes the catalog over anything added before it.
#   4. opnsense-rtl     the right-to-left layout.
#   5. os-theme-xgs     the XGS Silicon theme, after the layout: its installer has the layout mirror
#                       it at once, so Arabic has it from the first page. Then it is the GUI's theme -
#                       xgs-auto, light or dark as the browser's own setting says - which the owner
#                       changes in System: Settings: General like any theme.
#   6. the plugins      os-netreport, os-linkhealth, os-fanctl, and os-frontpanel when the image was
#                       built with a front panel (the build page's "Front panel").
#   7. turning them on  install/enable.sh, where a plugin has one. os-netreport and os-linkhealth
#                       are on as installed. os-fanctl comes on in its watch-only mode, which never
#                       writes to a fan chip. os-frontpanel comes on only where the plugin's own
#                       table has an entry for this model that was confirmed on the hardware;
#                       anywhere else it stays off and the log says why.
#
# The GUI language is not touched: it stays English, OPNsense's default, with Arabic in the list.
# The GUI theme is: xgs-auto (step 5).
#
# Each piece keeps itself across OPNsense updates from then on - a pkg trigger and a boot hook of
# its own, installed by its own installer. This hook is only the first install.
#
# If something here does nothing: the pieces are under /usr/local/share/xgs-image/components and
# /usr/local/share/os-xgs-npu/source, and each one's installer can be run by hand as root.

SHARE=/usr/local/share/xgs-image
COMP=${SHARE}/components
DONE=${SHARE}/done
# Not under /var/log: on the install media this hook runs in live mode, and the installer clones
# /usr/local to the disk but not that log - measured, the installed system had every piece and no
# log of how they got there. Beside the markers it is copied with them.
LOG=${SHARE}/firstboot.log

mkdir -p "${DONE}"

log() {
    /usr/bin/logger -t xgs-image -p daemon.notice "$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "${LOG}"
}

# step <name> <command...>: once, marked when it succeeds; a failure is logged and retried next boot
step() {
    name=$1
    shift
    [ -f "${DONE}/${name}" ] && return 0
    log "${name}: installing"
    if "$@" >> "${LOG}" 2>&1; then
        date > "${DONE}/${name}"
        log "${name}: done"
    else
        log "${name}: failed - see ${LOG}; it is tried again at the next boot"
    fi
}

# 1. The driver. install.sh refuses a board this project has not run on, which is the behaviour
# wanted: an unknown appliance gets nothing rather than another board's pieces.
if [ -f /usr/local/share/os-xgs-npu/source/install/install.sh ]; then
    step os-xgs-npu /bin/sh /usr/local/share/os-xgs-npu/source/install/install.sh
fi

# 2. lcdproc, from the files, for the front panel; pkg add takes any missing dependency from the
# same directory. The files are in the image only when it was built with a front panel.
LCDPKG=$(ls "${SHARE}"/packages/All/lcdproc-*.pkg 2>/dev/null | head -1)
if [ -n "${LCDPKG}" ]; then
    step lcdproc /bin/sh -c "[ -x /usr/local/sbin/LCDd ] || pkg add '${LCDPKG}'"
fi

# 3 and 4. The translation, then the layout.
for c in opnsense-arabic opnsense-rtl; do
    [ -f "${COMP}/${c}/install.sh" ] && step "${c}" /bin/sh "${COMP}/${c}/install.sh"
done

# 5. The theme, then the GUI's theme set to it.
if [ -f "${COMP}/os-theme-xgs/install/install.sh" ]; then
    step os-theme-xgs /bin/sh "${COMP}/os-theme-xgs/install/install.sh"
    if [ -f "${DONE}/os-theme-xgs" ]; then
        step os-theme-xgs-enabled /bin/sh "${COMP}/os-theme-xgs/install/enable.sh" xgs-auto
    fi
fi

# 6. The plugins; os-frontpanel is here only when the image was built with a front panel.
for c in os-netreport os-linkhealth os-fanctl os-frontpanel; do
    [ -f "${COMP}/${c}/install/install.sh" ] && step "${c}" /bin/sh "${COMP}/${c}/install/install.sh"
done

# 7. On, where a plugin has a way to turn itself on - and only once it is installed.
for c in os-fanctl os-frontpanel; do
    if [ -f "${DONE}/${c}" ] && [ -f "${COMP}/${c}/install/enable.sh" ]; then
        step "${c}-enabled" /bin/sh "${COMP}/${c}/install/enable.sh"
    fi
done

exit 0
HOOK
chmod 0755 "${HOOKDIR}/00-xgs-image-firstboot"
say "first-boot hook installed"

# ------------------------------------------------------------------ close it cleanly

df -m "${MNT}" | awk 'NR==2 {printf "==> %s MB free left in the image\n", $4}'
sync
umount "${MNT}"
fsck_ffs -y "/dev/${PART}" >/dev/null 2>&1 || true
detach
say "done: ${IMG}"
