# Threat model

Defense-Up protects one path, from a commit on `main` to a container running on your machine. This page maps each control on that path to the attack it stops, then gives you commands to watch several of those controls fail closed.

The path covers the GitHub Actions workflows, the Dockerfile and its base images, the locked Python packages, the signed image in GHCR, the GitHub release, and the runtime settings in `docker-compose.yml`. The Flask app's own code, the host or cluster that runs the image, and the maintainer's laptop and GitHub account sit outside it.

## Which attack does each control stop?

| Control | Attack it stops | Where it lives |
| --- | --- | --- |
| Actions pinned to a full commit SHA | Someone who takes over an action's repository moves a version tag to malicious code. In March 2025 an attacker repointed the tags of `tj-actions/changed-files` at a commit that printed CI secrets into build logs, per [the GitHub advisory](https://github.com/tj-actions/changed-files/security/advisories/GHSA-mw4p-6x4p-x5m5). A SHA pin keeps running the commit it names. | Every `uses:` line in `.github/workflows/` |
| Repository SHA pinning policy | A new `uses: owner/action@v1` line gets past review. With [the policy GitHub added in August 2025](https://github.blog/changelog/2025-08-15-github-actions-policy-now-supports-blocking-and-sha-pinning-actions/) turned on, any workflow that references an action by tag or branch fails. | Settings, Actions, General |
| Base images pinned by digest | The registry or the upstream project points `latest` at a different image between two builds. | Both `FROM` lines in `Dockerfile` |
| Hash-locked pip with `--only-binary=:all:` | A swapped or tampered package file reaches the build, or a source distribution runs its own build code during install. | `requirements.txt` and the `pip install` step in `Dockerfile` |
| `permissions: {}` and per-job scopes | A compromised step uses the workflow token to push code, rewrite a release, or sign an image. Each job asks only for the scopes its comments name, and the job that runs Syft gets none. | The top of every workflow and each job's `permissions:` block |
| `persist-credentials: false` | A later step reads the token that `actions/checkout` would otherwise leave in `.git/config`. | Every `actions/checkout` step |
| No build cache in the release | A less trusted workflow writes a poisoned cache entry and the release build restores it. Researchers traced the first malicious Ultralytics releases in December 2024 to [an attack on the GitHub Actions cache](https://blog.pypi.org/posts/2024-12-11-ultralytics-attack-analysis/). `pr.yml` uses the Actions cache, and `release.yml` never reads it. | The `build` job in `.github/workflows/release.yml` |
| Tag guard | Someone pushes a release tag on a commit that never went through a pull request and the required checks. The guard rejects any tag outside `vMAJOR.MINOR.PATCH` and any commit that isn't an ancestor of `origin/main`. | The `guard` job in `release.yml` |
| Release tag ruleset | Someone deletes or moves a `v*` tag after it ships. The Protect release tags ruleset blocks deletion, force pushes, and updates on `refs/tags/v*`. | Settings, Rules |
| Required checks on `main` | A pull request merges while the image build, smoke test, Grype scan, zizmor, or dependency review is failing. | The Protect main ruleset in Settings, Rules |
| Push by digest, tag after verification | People pull a tag that points at an image nobody has checked yet. The build pushes an untagged index, and the `promote` job adds tags only after `verify` passes, then reads every tag back and compares digests. | The `build` and `promote` jobs in `release.yml` |
| `release` environment on the signing job | A tag push signs an image with no person in the loop. Once the environment has a required reviewer, the signing job waits for that approval. | `environment: release` on `sign-and-attest`, plus Settings, Environments |
| Keyless cosign signing | Someone steals a long-lived signing key, or signs an image from a different workflow. The short-lived certificate names `release.yml` and the exact tag, and there's no key to steal. | The `Sign image with cosign` step |
| Provenance attestation | Someone presents an image built from a different repository, commit, or workflow, or on a self-hosted runner. | The `Attest build provenance` step |
| Per-platform SBOM attestations | An SBOM that describes a different image than the one you run. The workflow attests each CycloneDX SBOM against the digest of its own platform image. | The `sbom` job and the two `Attest linux/... SBOM` steps |
| Verify gate | A signing or attestation step quietly fails or covers the wrong digest. A read-only job checks the signature, the provenance, and both SBOMs against the exact workflow identity, tag, and commit before the `promote` job tags anything. | The `verify` job in `release.yml` |
| Immutable releases | Someone swaps a release asset or moves its tag after publication. [Immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases) lock both and add a release attestation. The workflow uploads the SBOMs to a draft before it publishes. | Repository settings and the `release` job |
| Dependabot cooldown | A hijacked upstream release reaches a pull request the day it ships. Dependabot waits 7 days before proposing any new action, base image, or Python package. | `.github/dependabot.yml` |
| zizmor | Workflow mistakes such as template injection, unpinned actions, and broad token permissions. zizmor runs with the pedantic persona on every pull request and push to `main`. | `.github/workflows/zizmor.yml` |
| Dependency review | A pull request adds a dependency with a known high or critical vulnerability. | `.github/workflows/dependency-review.yml` |
| Grype scan on pull requests | The image picks up a high or critical vulnerability that has a fix, and the pull request merges anyway. | The scan step in `.github/workflows/pr.yml` |
| Daily rescan of the released image | A vulnerability gets disclosed after the release shipped. Grype scans `:latest` every day, fails on a fixable high or critical finding, and uploads the results to code scanning. | `.github/workflows/rescan.yml` |
| OpenSSF Scorecard | Repository settings drift, such as weaker branch protection. Scorecard reruns when a protection rule changes, weekly, and on every push to `main`. | `.github/workflows/scorecard.yml` |
| Distroless non-root runtime | An attacker with code execution in the app reaches for a shell, root, a package manager, or a writable filesystem. The runtime image has no shell and runs as user 65532. Compose mounts the root filesystem read-only, drops every capability, and blocks privilege escalation. | `Dockerfile`, `docker-compose.yml`, and the smoke test in `pr.yml` |
| Allowlisted `.dockerignore` | Secrets, `.git`, or workflow files end up in an image layer. Docker sends only `app/`, `tests/`, and `requirements.txt` to the builder. | `.dockerignore` |

## Try to break it

Run these from the repository root. The first four work today. The last one needs a release, and it works from the first release that the current `release.yml` builds. No such release exists yet, because older tags came from an earlier pipeline.

### Unpin an action

Copy a workflow, swap the checkout SHA for a tag, and audit the copy with [zizmor](https://docs.zizmor.sh).

```bash
cp .github/workflows/zizmor.yml /tmp/unpinned.yml
sed -i.bak -E 's#actions/checkout@[0-9a-f]{40}.*#actions/checkout@v7#' /tmp/unpinned.yml
zizmor --offline --persona pedantic /tmp/unpinned.yml
```

zizmor exits non-zero and reports a high `unpinned-uses` finding on the checkout line. If you push the same change in a pull request, zizmor flags the line on the pull request, and GitHub fails the workflow run because the repository requires SHA pins.

### Tamper with a hash

The lock lists two hashes for Flask, and pip accepts either one, so change the last character of both.

```bash
sed -e 's/f87c9eb /f87c9ec /' -e 's/1f670c$/1f670d/' requirements.txt > /tmp/tampered.txt
python3 -m venv /tmp/tamper-venv
/tmp/tamper-venv/bin/pip install --target=/tmp/pkgs --no-cache-dir \
  --require-hashes --only-binary=:all: -r /tmp/tampered.txt
```

pip downloads the real Flask wheel, compares it with the lock, and exits non-zero with `THESE PACKAGES DO NOT MATCH THE HASHES FROM THE REQUIREMENTS FILE`. It prints the expected and actual hashes and installs nothing.

### Run the container locked down

```bash
docker build -t defense-up:local .
docker run --detach --name hardened --read-only --cap-drop ALL \
  --security-opt no-new-privileges:true --publish 127.0.0.1:5002:5000 defense-up:local
curl --retry 10 --retry-delay 1 --retry-all-errors http://127.0.0.1:5002/
docker run --rm --read-only --entrypoint /usr/bin/python defense-up:local \
  -c "open('/app/pwned', 'w')"
docker run --rm --entrypoint /bin/sh defense-up:local
docker rm --force hardened
```

The app still answers with its hello message under `--read-only` and `--cap-drop ALL`. The write attempt fails with `Read-only file system`, and the shell attempt fails because the image has no `/bin/sh`.

### Verify with the wrong identity

Chainguard signs its base images with cosign, so you can practice on the runtime base image before Defense-Up has a release. You need cosign v3, the same version the README asks for.

```bash
BASE=$(grep -oE 'cgr.dev/chainguard/python:latest@sha256:[0-9a-f]{64}' Dockerfile)
cosign verify "${BASE}" \
  --certificate-identity https://github.com/chainguard-images/images/.github/workflows/release.yaml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
cosign verify "${BASE}" \
  --certificate-identity https://github.com/onlydole/defense-up/.github/workflows/release.yml@refs/tags/v1.0.0 \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

The first command passes. The second exits non-zero with `no matching signatures`, because a valid signature from the wrong workflow still fails an exact identity check.

### Break the release checks

Set `TAG`, `IMAGE`, and `DIGEST` the way the README does, then look up the amd64 image inside the index.

```bash
DIGEST_AMD64=$(docker buildx imagetools inspect --raw "${IMAGE}@${DIGEST}" \
  | jq -r '.manifests[] | select(.platform.architecture == "amd64") | .digest')

cosign verify "${IMAGE}@${DIGEST}" \
  --certificate-identity "https://github.com/onlydole/defense-up/.github/workflows/release.yml@refs/tags/v9.9.9" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

cosign verify "${IMAGE}@${DIGEST_AMD64}" \
  --certificate-identity "https://github.com/onlydole/defense-up/.github/workflows/release.yml@refs/tags/${TAG}" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

gh attestation verify "oci://${IMAGE}@${DIGEST}" -R onlydole/defense-up \
  --signer-workflow onlydole/defense-up/.github/workflows/pr.yml
```

We expect all three to exit non-zero. The first names a tag the certificate doesn't contain. The second asks about the platform digest, and the workflow signs only the index digest. The third asks for an attestation from `pr.yml`, which never signs anything. Swap in the right tag, the index digest, or `release.yml`, and each check passes.

## SLSA level

GitHub's docs say that [artifact attestations by themselves provide SLSA v1.0 Build Level 2](https://docs.github.com/en/actions/concepts/security/artifact-attestations). Each release that the current `release.yml` builds reaches Build L2. GitHub-hosted runners build the image, and `actions/attest` signs the provenance through Sigstore with the workflow's identity.

Build L3 asks the build platform to keep runs from influencing each other and to keep signing material away from user-defined build steps, per the [SLSA v1.2 build track](https://slsa.dev/spec/v1.2/build-track-basics). GitHub's route there is to [move the build and attestation into a reusable workflow](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/increase-security-rating) and verify with `--signer-workflow` pointing at that reusable workflow. `release.yml` signs in a separate job from the build, but the same workflow file defines both, so we don't claim L3.

## Known gaps

- **One maintainer.** The Protect main ruleset requires a pull request and passing checks, but zero approving reviews. CODEOWNERS names one person, so nobody else reads a change before it merges.
- **No reviewer on the `release` environment yet.** The repository has no `release` environment configured, so nothing pauses the signing job for approval until someone adds a required reviewer.
- **GitHub is trusted.** The runners, the OIDC tokens, GHCR, the attestations API, and the Sigstore services behind keyless signing all sit inside the trust boundary. A compromise of any of them defeats these checks.
- **The base image version floats.** [Chainguard's free tier](https://www.chainguard.dev/docs/chainguard/containers/concepts/container-categories) publishes only `latest` and `latest-dev`. The digest pin freezes each build, but any Dependabot digest bump can move Python to a new major or minor version with no tag change to warn you.
- **BuildKit's provenance has no signature of its own.** `provenance: mode=max` stores BuildKit's record in the image index as a plain attestation. The signed provenance is the GitHub attestation, so verify that one.
- **No VEX document.** Scanners report every match in the SBOM, and Defense-Up publishes no statement about which findings don't affect the app.
- **Builds aren't reproducible.** We haven't made the build bit-for-bit reproducible, so you can't check a release by rebuilding its commit and comparing digests.
