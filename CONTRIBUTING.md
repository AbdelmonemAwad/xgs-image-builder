# Contributing

Read this before writing anything here. These are the project's rules, not suggestions, and they
are in the repository rather than in a prompt because a rule that lives in a prompt gets forgotten -
that is not hypothetical, it is why this file exists.

## Publishing

- **No AI attribution anywhere.** Not in a commit message, not in a pull request title or body, not
  in an issue, not in a comment. No line, no emoji, no link. If your tooling adds one, remove it
  before you submit.
- **English only** in code, in documentation and in anything published here.
- **Pull requests, never a direct push to `main`.**
- **Claim only what is tested.** Nothing here is built or booted by CI on real hardware, so say so
  plainly instead of implying it works.

## What this repository is

A **recipe**, not an image. It builds a bootable OPNsense image for Sophos XGS appliances with the
[os-xgs-npu](https://github.com/AbdelmonemAwad/os-xgs-npu) driver and plugin installed, and it
stores no part of the upstream image.

The build runs in GitHub Actions from a `workflow_dispatch` with dropdown inputs. The result is a
workflow artifact with a short retention, not a release asset and not a committed file.

**That shape is deliberate and it is also the licence position.** Running a workflow needs write
access, so anyone else has to fork this repository and run it in their own account: their build,
their artifact, their storage. This repository distributes only its own code, and the user takes
the OPNsense image from OPNsense's own mirror under OPNsense's own terms.

## What it is not

- **Not pfSense.** pfSense is FreeBSD, not Linux, so the driver is not the obstacle - Netgate's
  position on derivatives and the availability of its kernel sources are. Out of scope.
- **Not Linux.** The driver is written against FreeBSD KPIs throughout: `if_t`, `taskqueue_thread`,
  `mtx`, `bus_space`, `ifmedia`, the net epoch. A Linux firewall distribution would need a second
  driver, not a port, and it would derive from the vendor's GPL source - so it belongs in a
  separate repository under a different licence.
- **Not an abstraction layer** over operating systems we do not have a driver for. Write for
  OPNsense. The sibling project lost three review rounds and 113 lines to machinery invented for a
  need that had not arrived.

## Two rules about the image itself

**All families in one image, selected at run time.** Install the whole project. The selection
already exists and is proven: `install.sh` branches by family, and each boot hook guards on its
own PCI id and exits cleanly when its hardware is absent. Note that a PCI id identifies the
*family*; the *board* comes from DMI, and port maps differ by board. Use both.

**No prebuilt module in the image.** A module built against a different kernel **loads silently**,
so an image carrying one is broken by the first kernel update. Ship the sources, the boot hooks and
`kernel-follow.sh`, and let the appliance build it on first boot.
