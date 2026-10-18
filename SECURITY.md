# Security

## Reporting a vulnerability

**Not in a public issue, please.** Report it privately through GitHub -
[**Report a vulnerability**](https://github.com/AbdelmonemAwad/xgs-image-builder/security/advisories/new),
on the Security tab - where only you and the owner see it, and the fix can be prepared before anything is
public. Without a GitHub account, write to **eg2@live.com**. Either way, include:

- what is affected - the build workflows, the request from an issue, the build page and the image they produce;
- the appliance, the image's options and the version it was built from, and the OPNsense version;
- how to reproduce it, and what you saw.

This is one person's project, worked on in the evenings: expect an answer within days, not hours.
A fix is made in a pull request and the reporter credited in it, unless they ask not to be.

## What is supported

The newest version on `main`, and the newest release where there are releases. Fixes go there,
with no backports.

## Worth knowing before you report

- **A build runs in GitHub Actions from a request.** Anything that lets a request run its own commands in the workflow, or reach the workflow's token, is a vulnerability - report it here, privately, never as a build request.
- An image that carries something it should not - a key, a password other than OPNsense's own default, a file from the build machine - is a vulnerability too.
- **Never send a configuration backup.** It holds keys and passwords.
