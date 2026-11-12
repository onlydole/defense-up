# Defense-Up

[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/onlydole/defense-up/badge)](https://scorecard.dev/viewer/?uri=github.com/onlydole/defense-up)

Defense-Up is a small Flask app that we use to demonstrate a hardened container supply chain. The app says hello. The pipeline around it signs the image, attests how it was built and what's inside it, and refuses to tag the image or publish a release until those checks pass.

## Quick start

```bash
docker compose up --build
```

The app listens on `http://localhost:5001`, on loopback only. Gunicorn serves it as a non-root user, with a read-only root filesystem and every Linux capability dropped.

Run the unit tests inside the builder image.

```bash
docker build --target test .
```

## What the pipeline does

- **Pins every action to a commit SHA.** Each `uses:` line points at a full 40-character commit with the version in a comment, so a moved or hijacked tag can't change what runs.
- **Pins base images by digest.** Both Dockerfile stages use the same Chainguard Python build, pinned by `sha256` digest, with the tag kept for readability.
- **Locks Python dependencies with hashes.** `pip install --require-hashes --only-binary=:all:` rejects any file that isn't in `requirements.txt` and never runs a package's build code.
- **Grants least privilege.** Every workflow starts with `permissions: {}`. Each job asks only for the scopes it needs, and every checkout sets `persist-credentials: false`.
- **Releases only what's on `main`.** The release workflow accepts `vMAJOR.MINOR.PATCH` tags only, and stops unless the tagged commit is on `main`. A tag on an unreviewed branch never gets built.
- **Builds releases without a cache.** The release build skips the shared Actions cache, so a poisoned cache entry can't end up in a signed image.
- **Signs keylessly.** cosign signs the image digest with a short-lived certificate tied to the release workflow's identity. There's no long-lived signing key to leak.
- **Attests provenance and an SBOM per platform.** GitHub artifact attestations record how the image was built and a CycloneDX SBOM of what's inside it. Each platform image gets its own SBOM, attested against that platform's digest. The attestations live in the GitHub attestations API and next to the image in GHCR.
- **Gates the tags and the release on verification.** The build pushes the image by digest with no tag. A read-only job verifies the signature and every attestation against that digest. Only then does the workflow add the version tags and `latest`, and publish the GitHub release. A failed check leaves nothing pullable by name.
- **Asks a person before signing.** The signing job runs in the `release` environment, which can require a reviewer and limit which tags may deploy.
- **Publishes the SBOMs with the release.** The release workflow attaches both SBOMs to a draft release and then publishes it, which works with immutable releases.
- **Waits before updating.** Dependabot keeps actions, base images, and Python packages current, with a 7-day cooldown. A new upstream release waits a week before Dependabot proposes it, which gives maintainers and scanners time to catch a bad one.
- **Audits the workflows.** [zizmor](https://docs.zizmor.sh) checks every workflow on each PR and push to `main`. Dependency review fails any PR that adds a dependency with a known high or critical vulnerability.
- **Scans the image.** [Grype](https://github.com/anchore/grype) scans the image on every PR and fails on a high or critical vulnerability that has a fix. A daily job rescans the released `latest` image, because a clean release can pick up known vulnerabilities later.
- **Tests and locks down the runtime.** Every PR runs the unit tests in the builder image, then starts the container with a read-only root filesystem, no capabilities, and no privilege escalation.
- **Scores itself.** [OpenSSF Scorecard](https://scorecard.dev) grades the repository's settings every week and after each push to `main`.

[docs/threat-model.md](docs/threat-model.md) maps each control to the attack it stops, with exercises that show the checks failing closed.

## Verify it yourself

The commands below work for releases that the current release workflow builds. Older releases used an earlier pipeline. Install [cosign](https://docs.sigstore.dev/cosign/system_config/installation/) v3 and the [GitHub CLI](https://cli.github.com), then pick a tag and look up its digest.

```bash
TAG=v1.0.0
IMAGE=ghcr.io/onlydole/defense-up
DIGEST=$(docker buildx imagetools inspect "${IMAGE}:${TAG}" --format '{{.Manifest.Digest}}')
```

Each release's notes list the same digest, so you can compare the two.

### Signature

The certificate identity must match the release workflow and the tag exactly.

```bash
cosign verify "${IMAGE}@${DIGEST}" \
  --certificate-identity "https://github.com/onlydole/defense-up/.github/workflows/release.yml@refs/tags/${TAG}" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

### Build provenance

The extra flags pin the attestation to the release workflow and the tag. Without them, an attestation from any workflow in the repository would pass.

```bash
gh attestation verify "oci://${IMAGE}@${DIGEST}" -R onlydole/defense-up \
  --signer-workflow onlydole/defense-up/.github/workflows/release.yml \
  --source-ref "refs/tags/${TAG}" \
  --deny-self-hosted-runners
```

### SBOM attestations

`DIGEST` names the multi-platform index. Each SBOM is attested against the platform image it describes, so look up that platform's digest first. The release notes list both.

```bash
PLATFORM_DIGEST=$(docker buildx imagetools inspect --raw "${IMAGE}@${DIGEST}" \
  | jq -r '.manifests[] | select(.platform.os == "linux" and .platform.architecture == "amd64") | .digest')

gh attestation verify "oci://${IMAGE}@${PLATFORM_DIGEST}" -R onlydole/defense-up \
  --signer-workflow onlydole/defense-up/.github/workflows/release.yml \
  --source-ref "refs/tags/${TAG}" \
  --predicate-type https://cyclonedx.org/bom \
  --deny-self-hosted-runners
```

Swap `amd64` for `arm64` to check the other platform.

### Release and SBOM assets

`gh release verify` checks the release attestation that GitHub creates for immutable releases.

```bash
gh release verify "${TAG}" -R onlydole/defense-up
gh release download "${TAG}" -p 'container-sbom-linux-*.json' -R onlydole/defense-up
gh release verify-asset "${TAG}" container-sbom-linux-amd64.json -R onlydole/defense-up
gh release verify-asset "${TAG}" container-sbom-linux-arm64.json -R onlydole/defense-up
```

## Enforce it in a cluster

Signing only helps if something checks the signature before the image runs. [deploy/kubernetes](deploy/kubernetes) has a hardened Deployment pinned by digest and a Kyverno policy that rejects any pod whose image lacks a signature and provenance from the release workflow.

## How a release runs

Pushing a tag that starts with `v` starts `.github/workflows/release.yml`. The jobs run in order, and each one gets only the permissions it needs.

1. **Check the tag** confirms the tag is a plain semantic version and the tagged commit is on `main`.
2. **Build and push image by digest** builds `linux/amd64` and `linux/arm64` images, pushes them to GHCR with no tag, and records BuildKit provenance.
3. **Generate SBOMs** runs Syft against each platform image with no token permissions.
4. **Sign and attest image** waits for the `release` environment, signs the index digest with cosign, and creates the provenance attestation and one SBOM attestation per platform.
5. **Verify signature and attestations** checks all of them with read-only permissions.
6. **Tag the verified image** adds the version tags and `latest` to the verified digest, then reads each tag back to confirm it.
7. **Publish GitHub release** creates the release with the SBOMs attached and the verify commands in the notes.

## Project structure

```text
defense-up/
├── .github/
│   ├── CODEOWNERS                    # Review ownership for every path
│   ├── dependabot.yml                # Dependabot updates with a 7-day cooldown
│   ├── pull_request_template.md      # Supply chain checklist for PRs
│   └── workflows/
│       ├── dependency-review.yml     # Blocks PRs that add vulnerable dependencies
│       ├── pr.yml                    # Tests, multi-arch build, smoke test, and image scan
│       ├── release.yml               # Guard, build, sign, attest, verify, tag, and publish
│       ├── rescan.yml                # Daily vulnerability scan of the released image
│       ├── scorecard.yml             # OpenSSF Scorecard
│       └── zizmor.yml                # Workflow security audit
├── app/                              # Flask application
├── deploy/kubernetes/                # Hardened Deployment and Kyverno admission policy
├── docs/threat-model.md              # What each control stops, and how to test it
├── tests/                            # Unit tests, run in the Dockerfile test stage
├── Dockerfile                        # Builder, test, and runtime stages on pinned Chainguard images
├── docker-compose.yml                # Local run with a locked-down container
├── requirements.in                   # Direct dependencies
└── requirements.txt                  # Locked dependencies with hashes
```

## Security

See [SECURITY.md](SECURITY.md) to report a vulnerability.

## License

This project uses the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
