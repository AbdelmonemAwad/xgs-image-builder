# xgs-image-builder

Build a bootable OPNsense image for a Sophos XGS appliance, with the
[os-xgs-npu](https://github.com/AbdelmonemAwad/os-xgs-npu) driver and plugin already in it.

> [!WARNING]
> **Nothing built here has been booted on an appliance.** The build runs on a GitHub runner, which
> has no Sophos hardware attached to it and never will. Burn an image and boot it before relying
> on it.

## How it is meant to be used

1. **Fork this repository.** You have to - running a workflow needs write access to the repository
   it runs in.
2. Open **Actions**, pick the build workflow, press **Run workflow**, and choose from the
   dropdowns: the OPNsense version, the image type, the console speed, and which commit of the
   driver project to install.
3. When it finishes, download the artifact and write it to a USB stick.

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

## What is in the image

Everything the project supports, for every appliance family, with the selection made **at first
boot** rather than at build time: the installer branches by family, and each boot hook checks for
its own hardware and exits quietly when it is not there. One image, any supported board.

The driver is **not** shipped prebuilt. It is built on the appliance against that kernel's own
sources, on first boot, because a module built against a different kernel loads silently and
would be broken by the first update.

## Before you change anything here

Read [CONTRIBUTING.md](CONTRIBUTING.md). It carries the publishing rules and the two decisions that
shape the image, and it is short.

## Status

Nothing here is finished. See the issues.
