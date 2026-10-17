# xgs-image-builder

Build a bootable OPNsense image for a Sophos XGS appliance, with the
[os-xgs-npu](https://github.com/AbdelmonemAwad/os-xgs-npu) driver and plugin already in it, and
the Arabic translation, the right-to-left layout and four appliance plugins beside it.

**[Open the build page](https://abdelmonemawad.github.io/xgs-image-builder/)** - pick the OPNsense
release, the image type and the console speed, and start the build. Nothing to install.

That link is this repository's own page, and a build only runs for the account that owns the
repository it runs in. So it is the one to read; it is not the one to build from. For an image of
your own, fork this repository and use **your fork's** copy of the page, at
`https://<your-account>.github.io/<your-fork>/`. The page works out which repository to file
against from its own URL, so your fork's page files on your fork and builds in your account. Each
page is live once Pages is turned on for that repository - step 2 below.

> [!WARNING]
> ~~**Nothing built here has been booted on an appliance.**~~ **One image built here has been
> installed on an appliance**: OPNsense 26.7, serial, 38400 baud, on an XGS 3300 (2026-10-16), which
> then assigned its own front ports at its first boot from disk. No other combination has been
> booted. The build runs on a GitHub runner, which has no Sophos hardware attached to it and never
> will. Burn an image and boot it before relying on it.

## How it is meant to be used

1. **Fork this repository.** You have to - running a workflow needs write access to the repository
   it runs in.
2. **Turn on Pages for your fork** - Settings -> Pages -> source: branch `main`, folder `/docs`.
3. Open your fork's **build page** and choose from the dropdowns: the OPNsense release, the image
   type, the console speed, whether the console is serial-only, and which commit of the driver
   project to install. Press the button; it fills in a build request and you submit it. A workflow
   picks it up and starts the build.

   Your fork's page is at `https://<your-account>.github.io/<your-fork>/`, and the original's -
   worth a look before you fork - is at <https://abdelmonemawad.github.io/xgs-image-builder/>.

   There are two ways to start it, and the difference between them is a token.

   **Build it** - no token. GitHub opens in a new tab with the request filled in; press **Submit
   new issue** there and come back. The page then reads the request back, shows whatever the
   repository answers - including a refusal, within seconds - and follows the build to the
   download.

   *That one press is not a detour, it is the authentication.* A page cannot file an issue for
   you: creating one through the API needs a token, submitting GitHub's own form for you is
   blocked cross-origin, and GitHub refuses to be put in a frame. So the press stays, and it is
   what makes this route need no credential at all. Everything after it is automatic - the request
   carries an id, the workflow puts it in the run's name, and the page follows the issue and then
   the run. Those reads are made with no credential, which **a public repository allows and a
   private one does not**, and GitHub allows sixty of them an hour per address, so the page slows
   its polling as the wait goes on and says plainly if the allowance runs out.

   **Fork and build in my account** - with a token, and it does the whole thing. It forks this
   repository into your account if you have not already, turns workflows on for the fork, builds
   there, and hands you the image. No issue, no new tab, no steps. That is what a token buys, and
   it is the only thing that can buy it: forking, filing an issue and dispatching a workflow all go
   through the REST API, which has no door that does not want a credential.

   The token has to cover **creating a repository** - a fork is a new one - and **Actions: Read and
   write**. A [classic token with `repo` and
   `workflow`](https://github.com/settings/tokens/new?scopes=repo,workflow) is the one that
   certainly does both. It is sent to `api.github.com` and nowhere else, never put in a URL, and
   held in the tab unless you tick the box to keep it in that browser. **No credential lives in the
   page itself.**

   The page is static either way: it loads nothing from anywhere, and every style, icon and line of
   script is in the one file.

   If you would rather skip the page, the same dropdowns are the workflow's own inputs:
   **[Build image -> Run workflow](../../actions/workflows/build.yml)**. That is where GitHub
   renders them, and the only place it can - a README cannot hold them, because GitHub strips
   `<form>`, `<select>` and `<input>` out of Markdown.
4. When it finishes, download the artifact and write it to a USB stick.

The artifact expires on its own. Nothing is kept.

## Why it works this way

This repository holds **no part of any OPNsense image**. The workflow fetches the official image
from OPNsense's own mirror at build time, verifies it, and adds this project's files to it.

That is not only to keep the repository small. Because the build runs in *your* fork, under *your*
account, the image is something you built for yourself from an upstream image you obtained from
upstream. This repository distributes its own code and nothing else.

OPNsense is a trademark of Deciso B.V. Nothing here is endorsed by or affiliated with them, and the
name is used only to say which system the image is built from.

## The console speed matters more than it looks

An XGS appliance has no screen. OPNsense defaults its serial console to **115200**, and Sophos
firmware uses **38400** on the same port. Choose the wrong one and the appliance boots perfectly
into a console you cannot read. The dropdown exists for that reason.

The speed chosen is written everywhere the port's speed is decided, not only in the loader: the
loader (`/boot/loader.conf.local`), the boot blocks (`/boot.config`), and OPNsense's own default
configuration (`serialspeed` in `/usr/local/etc/config.xml`). The last one matters most. At every
boot OPNsense rewrites the login prompt's speed in `/etc/ttys` from that setting, and the serial
image ships 115200 - so until 2026-10-16 an image built for 38400 booted readably and then printed
its login prompt at 115200, which a 38400 terminal shows as garbage. With "serial only" off, the
screen is set as the second console too, so it gets a login prompt of its own.

## What is in the image

Everything the project supports, for every appliance family, with the selection made **at first
boot** rather than at build time: the installer branches by family, and each boot hook checks for
its own hardware and exits quietly when it is not there. One image, any supported board.

The driver is **not** shipped prebuilt. It is built on the appliance against that kernel's own
sources, on first boot, because a module built against a different kernel loads silently and
would be broken by the first update.

Beside the driver, each from its own repository at the ref [components.list](components.list)
names, and each recorded by commit in the build's summary:

| | what it is | on after first boot |
|---|---|---|
| [opnsense-arabic](https://github.com/AbdelmonemAwad/opnsense-arabic) | the GUI in Arabic | in the language list; the GUI **stays English** until Arabic is chosen |
| [opnsense-rtl](https://github.com/AbdelmonemAwad/opnsense-rtl) | the right-to-left layout for it | applied; it shows only when the language is Arabic or Persian |
| [os-netreport](https://github.com/AbdelmonemAwad/os-netreport) | scheduled network reports | on as installed |
| [os-linkhealth](https://github.com/AbdelmonemAwad/os-linkhealth) | port and cable health | on as installed |
| [os-fanctl](https://github.com/AbdelmonemAwad/os-fanctl) | fans and temperatures | on, in its watch-only mode: it never writes to a fan chip until a curve is chosen |
| [os-frontpanel](https://github.com/AbdelmonemAwad/os-frontpanel) | the LCD and keys | in the image **only when the build page's "Front panel" is yes** - a rack model such as the XGS 3300; a desktop such as the XGS 136 has none - and on where the plugin's own table has a confirmed entry for the model |

The front panel needs LCDproc, so when the front panel is asked for its packages are fetched at
build time from the OPNsense
repository the image itself is set up for, and installed from those files at first boot: on an
XGS 3300 there is no network until the driver exists, because the WAN is one of the
coprocessor's own ports.

**The order is fixed, and it matters.** The first-boot hook in `scripts/inject.sh` installs the
driver first (the network may depend on it), then LCDproc where there is a panel, then the translation (three plugins add
their own Arabic strings to its catalog and skip a language whose catalog is missing), then the
layout, then the plugins, then turns them on. Each step is done once and marked; one that fails is
logged in `/usr/local/share/xgs-image/firstboot.log` and tried again at the next boot, and does not stop the
others.

**Each piece keeps itself across OPNsense updates.** An update replaces the files the translation,
the layout and the plugins' strings live in, and an update that only installs packages does not
reboot. So each installs a pkg trigger, which pkg runs the moment an update writes into those
directories, and a boot hook - in its own repository, where the change belongs.

**And each keeps itself up to date.** The driver from System - Firmware - XGS Coprocessor, the
others by themselves once a day from their own repository's latest release. Both move only
forward from what is installed, which they read from the commit this builder writes into each tree
as `.source-commit` (the driver's as `.image-build`): with `.git` removed from the image that is the
only record of it, and without it a release older than the image would be taken.

## Why only 26.7 in the release list

Because the driver needs FreeBSD 15. It uses FreeBSD's IPsec offload interface
(`netipsec/ipsec_offload.h`, `IFCAP2_IPSEC_OFFLOAD`), which OPNsense has from 26.7 on; 26.1 and the
25.x releases are FreeBSD 14.x, and the module does not compile there. An image of one of those
would boot with no front ports and, on an XGS 3300, no WAN. A newer release goes into the list once
it is published and checked against the same two names.

## Before you change anything here

Read [CONTRIBUTING.md](CONTRIBUTING.md). It carries the publishing rules and the two decisions that
shape the image, and it is short.

## Status

Nothing here is finished. See the issues.

- **Installing an image** is on the build page, step by step, for as long as the driver project's
  work-in-progress notice stands: write the image to a stick, boot it, install to the disk, and at
  the first boot from the disk a thirty-second countdown on the console assigns the front ports -
  WAN on Port2 (XGS 3300) or Port1 (XGS 136), every other front port in one bridge as LAN on
  192.168.1.1, and the management port, where there is one, as MGMT on 192.168.100.1. A key during
  the countdown leaves the assignment to OPNsense's own menu.
- **What the driver project measured on the appliances since** - IPsec with the coprocessor's engine
  at both ends of a tunnel, jumbo frames through the switch chip, the MTU from 576 to 9000 - is in
  its [measurements](https://github.com/AbdelmonemAwad/os-xgs-npu/tree/main/docs/measurements);
  an image built here installs that project, so it carries all of it.
