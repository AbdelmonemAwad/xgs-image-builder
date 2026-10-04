# The two board maps, and which one decides what

`CONTRIBUTING.md` says a PCI id identifies the *family*, the *board* comes from DMI, port maps
differ by board, and to use both. This page is the detail behind that sentence, and the reason the
build in this repository reads neither.

Both maps live in `os-xgs-npu`. They answer different questions and neither substitutes for the
other.

## Map 1: the PCI identity, which gives the family

From that project's `compat.json`:

| family | PCI id | driver |
|---|---|---|
| ARMADA | `11ab:7080` | `npuep` |
| OCTEON TX | `177d:a300` | `octep` |

Read at run time by the boot hook, which matches both spellings `pciconf` prints:

    pciconf -l | grep -qE 'chip=0xa300177d|vendor=0x177d[[:space:]]+device=0xa300'
    - src/etc/rc.syshook.d/early/08-octep

That hook's own comment records why both: matching only the packed `chip=` form made it skip on the
very appliance it was written for, silently.

**It gives the family and nothing finer.** One identity covers every board built on that
coprocessor - `board.sh` annotates assembly 201 as "XGS 126 / 136", two appliances behind one id.

Use it for: whether to load a driver, whether a boot hook has work to do.

## Map 2: the assembly number from SMBIOS, which gives the board

From `src/opnsense/scripts/xgs/board.sh`, which reads the serial of SMBIOS type 2:

    SERIAL=${XGS_PLANAR_SERIAL:-$(/bin/kenv -q smbios.planar.serial 2>/dev/null)}
    BOARD=$(echo "${SERIAL}" | /usr/bin/sed -n 's/.*AMDA0*\([0-9][0-9]*\)-.*/\1/p')

| assembly | prints | appliances |
|---|---|---|
| 201 | `201 armada` | XGS 126 / 136 |
| 202 | `202 octeontx` | the 1U desktops; run on the XGS 3300 |
| anything else | `<n> untested`, exit 1 | refuses rather than guessing |

Use it for: anything that differs between boards sharing a coprocessor - port maps, reset lines,
CPLD polarity.

**The project already paid for getting this wrong.** `board.sh`'s comment records it: the board used
to be decided by elimination - no OCTEON TX endpoint on PCI, so this must be the ARMADA appliance -
and the reset tool carried the XGS 136's board number as a constant. On the XGS 3300 that sent the
136's pin values to the 3300's MCP2210, which on that board drives the coprocessor's reset and boot
flash, and the coprocessor left the bus until the bridge was put back to its power-on state.
`src/opnsense/scripts/npuctl/mcp2210.py` states the general case: *"the polarity is NOT the same
across boards - AMDA0200 is the exact inverse of ours."*

And there is a second reason PCI cannot stand in for this: on the XGS 136 the coprocessor comes out
of power-on **held in reset**, so it is not on the bus at the moment the hook that releases it has
to decide what to release.

## The two maps do not agree on spelling, which is a trap for anything that joins them

| | family | assembly |
|---|---|---|
| `board.sh` output | `armada`, `octeontx` | numeric: `201`, `202` |
| `compat.json` `boards[]` | `ARMADA`, `OCTEON_TX` | string: `AMDA0201`, `AMDA0202-0004` |

Two differences, and the second is sharper:

1. **Case and separator.** `octeontx` against `OCTEON_TX`. A comparison between them never matches,
   and never errors either.
2. **The suffix.** `compat.json` records the XGS 136 as `AMDA0201`, with nothing after it, while
   `board.sh`'s expression requires a `-` after the digits. Feed `compat.json`'s own `assembly`
   string through `board.sh`'s regex and it extracts nothing for one of the two boards it describes.

Nothing in the project compares them today - `compat.json` is read only by its upstream-watch
workflow, and only for the release number - so this is latent rather than broken. Anything that
joins the two has to normalise first and refuse what it cannot resolve, never compare the raw
strings.

## What this build uses each for: neither

| decision | where it is made |
|---|---|
| which driver sources go in the image | neither map - all of them go in |
| which boot hooks get installed | map 2, by the project's own `install.sh`, **on the appliance** |
| whether a hook acts at boot | map 1, PCI, **on the appliance** |
| which board's port map applies | map 2, **on the appliance** |
| what this build decides about hardware | **nothing** |

The last row is the point, and it is why one image can cover every family. A GitHub runner has no
appliance in it to read either map from, so the build cannot make a hardware decision even in
principle - and it does not try. `scripts/inject.sh` installs the project whole and drops a
first-boot hook that runs `install.sh` on the real machine, where both maps are readable and where
`install.sh` already refuses a board the project has not been run on.

That is also why the build is honest about what it produced: an image, not a working appliance.
