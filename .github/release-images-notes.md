**Ready-made OPNsense images for Sophos XGS appliances**, with
[os-xgs-npu @VERSION@](https://github.com/AbdelmonemAwad/os-xgs-npu/releases/tag/@TAG@) installed.
Download one, write it to a USB stick, and boot the appliance from it.

| Image | For |
|---|---|
| `xgs-opnsense-26.7-serial-38400-front-panel.img.xz` | the rack models, an LCD and keys on the front - XGS 2100, 2300, 3100, 3300 - console at 38400 baud |
| `xgs-opnsense-26.7-serial-38400.img.xz` | the desktop models, no front panel - XGS 87, 107, 116, 126, 136, 138 and their w twins - console at 38400 baud |
| `xgs-opnsense-26.7-serial-115200-front-panel.img.xz` | the rack models, console at 115200 baud |
| `xgs-opnsense-26.7-serial-115200.img.xz` | the desktop models, console at 115200 baud |

Each image is for every model of its kind: it carries both drivers - ARMADA for the desktop models,
OCTEON TX for the rack ones - and the kernel sources they are built from, and at its first boot the
appliance installs the one its own board names. Only the front panel plugin sets the images apart.
The XGS 136 and the XGS 3300 are the two run by the project; the other models are added from the
vendor's board files and untested.

All four put the console on the serial port alone: an XGS has no video output. **38400 baud** is the
speed the Sophos firmware uses on the same port, so the terminal settings that worked before work
there; **115200** is OPNsense's own default. Choose the one your terminal is set to - the wrong one
boots perfectly into a console you cannot read.

## What is in them

- **The official OPNsense 26.7 image**, fetched from OPNsense's own mirror and checked against the
  checksum list OPNsense publishes. Nothing in it is changed except what is added below, and
  OPNsense's copyright and licence notices are kept as they are.
- **os-xgs-npu @VERSION@** - the driver as sources, built on the appliance at its first boot against
  the kernel it runs. No module is built in advance: one built for a different kernel loads without
  complaint and then reads its structures at the wrong offsets.
- The Arabic translation and the right-to-left layout (the GUI stays in English until Arabic is
  chosen), the XGS Silicon theme, and the appliance plugins - with, in the front-panel images, the
  front panel plugin and the LCDproc packages it needs. All installed at the first boot, each keeping
  itself across OPNsense updates.

## Before relying on one

> **These four files have not been booted on an appliance.** They are built on a GitHub runner, which
> has no Sophos hardware attached to it. Images from the same build have been installed on an XGS 3300
> and on an XGS 136 - [which ones, and what was checked](https://github.com/AbdelmonemAwad/xgs-image-builder#readme) -
> but not these. Boot one before relying on it.

Check the download against `SHA256SUMS`, below and attached:

- Linux or macOS: `sha256sum -c SHA256SUMS --ignore-missing`
- Windows (PowerShell): `Get-FileHash .\<file>.img.xz -Algorithm SHA256`

Writing the stick, installing to the disk and the first boot are on
[the build page](https://build.npuforge.org/#install_steps), step by step. This release was built by
[this run](@RUN_URL@), whose log shows every step and the commit of everything that went in.

An image for another console speed or another OPNsense release is built from
[the same page](https://build.npuforge.org/), in your own account.

## Notices

**OPNsense&reg;** is a registered trademark of Deciso B.V.; **Sophos&reg;** and **XGS** are trademarks
of Sophos Ltd. This project is independent: it is not affiliated with, endorsed by or sponsored by
either, and their names are used only to say what these images are made from and run on. OPNsense is
published under the BSD 2-Clause licence; its sources are at <https://github.com/opnsense>.

No Sophos software or firmware is in these images. If you hold rights in anything here and think it
should not be, write to [contact@npuforge.org](mailto:contact@npuforge.org): it will be looked at
promptly, and corrected or taken down if it should be.
