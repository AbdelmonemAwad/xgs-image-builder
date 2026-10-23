# Contributing

Read this before writing anything here. These are the project's rules, not suggestions, and they
are in the repository rather than in a prompt because a rule that lives in a prompt gets forgotten -
that is not hypothetical, it is why this file exists.

## Publishing

- **English only** in code, in documentation and in anything published here.
- **Pull requests, never a direct push to `main`.**
- **Claim only what is tested.** Nothing here is built or booted by CI on real hardware, so say so
  plainly instead of implying it works.

## What this repository is

A **recipe**, not an image. It builds a bootable OPNsense image for Sophos XGS appliances with the
[os-xgs-npu](https://github.com/AbdelmonemAwad/os-xgs-npu) driver and plugin installed, and it
stores no part of the upstream image.

The build runs in GitHub Actions from a `workflow_dispatch` with dropdown inputs. The result is a
workflow artifact with a short retention, not a committed file. ~~not a release asset~~ The same
build, called by `release-images.yml`, also makes the ready-made images published as a release for
each os-xgs-npu release - see below.

~~**That shape is deliberate and it is also the licence position.** Running a workflow needs write
access, so anyone else has to fork this repository and run it in their own account: their build,
their artifact, their storage. This repository distributes only its own code, and the user takes
the OPNsense image from OPNsense's own mirror under OPNsense's own terms.~~

**Ready-made images are published here, and the licence position is OPNsense's answer.** On
2026-10-23 the OPNsense project answered the question directly: its licence and trademark terms
([its legal guidelines](https://opnsense.org/legal-guidelines/)) hold nothing back from publishing
images built on its own. So `release-images.yml` builds the most needed combinations for each
os-xgs-npu release and publishes them, and a fork still builds any other combination in its own
account. What that answer keeps in force, every release and every page that offers a download keeps:

- **A descriptive name only** - "based on OPNsense 26.7". A name or logo derived from OPNsense's
  needs the project's permission first, and there is none.
- **OPNsense's notices stay as they are**, in the image and beside it: the BSD licence asks for
  that, and nothing here removes or changes them.
- **Independent, and said so** - not affiliated with, endorsed by or sponsored by Deciso B.V. or the
  OPNsense project, on every page that offers an image.
- **No Sophos software or firmware** in any image.

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

## Conduct, vulnerabilities and questions

Everyone here is held to the [Code of Conduct](CODE_OF_CONDUCT.md). A vulnerability goes to the
address in [SECURITY.md](SECURITY.md), not into an issue. A problem or an idea goes into an issue
through its form, a pull request through its template, and a question into the project's
[Discussions](https://github.com/AbdelmonemAwad/os-xgs-npu/discussions).
