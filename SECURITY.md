# Security policy

## Reporting a vulnerability

Please report security issues privately through GitHub. Go to the [Security tab](https://github.com/onlydole/defense-up/security) and select **Report a vulnerability**, or open the [private reporting form](https://github.com/onlydole/defense-up/security/advisories/new) directly.

Please don't open a public issue, pull request, or discussion for a security problem.

Include the affected version or image digest, the steps to reproduce the issue, and the impact you expect. We'll reply in the advisory thread and keep you updated as we work on a fix.

## Supported versions

Defense-Up is a demonstration project. We fix security issues in the latest release only.

## Verifying releases

The release workflow signs each image with cosign and creates GitHub attestations for its build provenance and SBOMs. The [README](README.md#verify-it-yourself) lists the commands to check them.
