# Defense-Up

Defense-Up is a small Flask app that we use to demonstrate a hardened container supply chain. The app says hello. The pipeline around it signs the image, attests how it was built and what's inside it, and refuses to publish a release until those checks pass.

## Quick start

```bash
docker compose up --build
```

The app listens on `http://localhost:5001`. Gunicorn serves it inside the container as a non-root user.

## What the pipeline does

- **Pins every action to a commit SHA.** Each `uses:` line points at a full 40-character commit with the version in a comment, so a moved or hijacked tag can't change what runs.
- **Pins base images by digest.** Both Dockerfile stages use the same Chainguard Python build, pinned by `sha256` digest, with the tag kept for readability.
- **Locks Python dependencies with hashes.** `pip install --require-hashes --only-binary=:all:` rejects any file that isn't in `requirements.txt` and never runs a package's build code.
- **Grants least privilege.** Every workflow starts with `permissions: {}`. Each job asks only for the scopes it needs, and every checkout sets `persist-credentials: false`.
- **Builds releases without a cache.** The release build skips the shared Actions cache, so a poisoned cache entry can't end up in a signed image.
- **Signs keylessly.** cosign signs the image digest with a short-lived certificate tied to the release workflow's identity. There's no long-lived signing key to leak.
- **Attests provenance and the SBOM.** GitHub artifact attestations record how the image was built and a CycloneDX SBOM of what's inside it. The attestations live in the GitHub attestations API and next to the image in GHCR.
- **Gates the release on verification.** A read-only job verifies the signature and both attestations against the pushed digest. The workflow publishes the GitHub release only if that job passes.
- **Publishes the SBOM with the release.** The release workflow attaches the SBOM to a draft release and then publishes it, which works with immutable releases.
- **Waits before updating.** Dependabot keeps actions, base images, and Python packages current, with a 7-day cooldown. A new upstream release waits a week before Dependabot proposes it, which gives maintainers and scanners time to catch a bad one.
- **Audits the workflows.** [zizmor](https://docs.zizmor.sh) checks every workflow on each PR and push to `main`. Dependency review fails any PR that adds a dependency with a known high or critical vulnerability.

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

```bash
gh attestation verify "oci://${IMAGE}@${DIGEST}" -R onlydole/defense-up
```

### SBOM attestation

```bash
gh attestation verify "oci://${IMAGE}@${DIGEST}" -R onlydole/defense-up \
  --predicate-type https://cyclonedx.org/bom
```

### Release and SBOM asset

`gh release verify` checks the release attestation that GitHub creates for immutable releases.

```bash
gh release verify "${TAG}" -R onlydole/defense-up
gh release download "${TAG}" -p container-sbom.json -R onlydole/defense-up
gh release verify-asset "${TAG}" container-sbom.json -R onlydole/defense-up
```

## How a release runs

Pushing a tag that starts with `v` starts `.github/workflows/release.yml`. The jobs run in order, and each one gets only the permissions it needs.

1. **Build and push image** builds `linux/amd64` and `linux/arm64` images, pushes them to GHCR, and records BuildKit provenance.
2. **Generate SBOM** runs Syft against the pushed digest with no token permissions.
3. **Sign and attest image** signs the digest with cosign and creates the provenance and SBOM attestations.
4. **Verify signature and attestations** checks all three with read-only permissions.
5. **Publish GitHub release** creates the release with the SBOM attached and the verify commands in the notes.

## Project structure

```text
defense-up/
├── .github/
│   ├── dependabot.yml                # Dependabot updates with a 7-day cooldown
│   └── workflows/
│       ├── dependency-review.yml     # Blocks PRs that add vulnerable dependencies
│       ├── pr.yml                    # Multi-arch build and smoke test on PRs
│       ├── release.yml               # Build, sign, attest, verify, and publish
│       └── zizmor.yml                # Workflow security audit
├── app/                              # Flask application
├── Dockerfile                        # Two-stage build on pinned Chainguard images
├── docker-compose.yml                # Local run
├── requirements.in                   # Direct dependencies
└── requirements.txt                  # Locked dependencies with hashes
```

## Security

See [SECURITY.md](SECURITY.md) to report a vulnerability.

## License

This project uses the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
