# xgs-image-builder

Build a bootable OPNsense image for a Sophos XGS appliance, with the
[os-xgs-npu](https://github.com/AbdelmonemAwad/os-xgs-npu) driver and plugin already in it.

**[Open the build page](https://abdelmonemawad.github.io/xgs-image-builder/)** - pick the OPNsense
release, the image type and the console speed, and it opens the build request for you. No account,
no token, nothing to install.

That link is this repository's own page, and a build only runs for the account that owns the
repository it runs in. So it is the one to read; it is not the one to build from. For an image of
your own, fork this repository and use **your fork's** copy of the page, at
`https://<your-account>.github.io/<your-fork>/`. The page works out which repository to file
against from its own URL, so your fork's page files on your fork and builds in your account. Each
page is live once Pages is turned on for that repository - step 2 below.

> [!WARNING]
> **Nothing built here has been booted on an appliance.** The build runs on a GitHub runner, which
> has no Sophos hardware attached to it and never will. Burn an image and boot it before relying
> on it.

## How it is meant to be used

1. **Fork this repository.** You have to - running a workflow needs write access to the repository
   it runs in.
2. **Turn on Pages for your fork** - Settings -> Pages -> source: branch `main`, folder `/docs`.
3. Open your fork's **build page** and choose from the dropdowns: the OPNsense release, the image
   type, the console speed, whether the console is serial-only, and which commit of the driver
   project to install. Press the button; it fills in a build request and you submit it. A workflow
   picks it up and starts the build.

   Your fork's page is at `https://<your-account>.github.io/<your-fork>/`, and the original's -
   worth a look before you fork - is at
   <https://abdelmonemawad.github.io/xgs-image-builder/>. The page is static: it holds no
   credentials, calls no API and loads nothing from anywhere. All it does is send you to the
   repository's new-issue form with your choices already in the body, and GitHub's own form does
   the authenticating - which is why no token has to live in a web page. Nothing runs until you
   press Submit.

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
