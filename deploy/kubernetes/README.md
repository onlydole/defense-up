# Run defense-up on Kubernetes

The release workflow signs every image and attaches SLSA build provenance. These manifests make a cluster check that evidence before it runs anything in the `defense-up` namespace.

| File | What it does |
| --- | --- |
| `namespace.yaml` | Creates the `defense-up` namespace and enforces the Pod Security `restricted` profile. |
| `kyverno-image-policy.yaml` | Kyverno `ImageValidatingPolicy` that rejects any pod in the namespace unless every image is pinned by digest, signed by this repository's release workflow for a `vX.Y.Z` tag, and carries GitHub's SLSA provenance attestation from that same workflow. |
| `deployment.yaml` | Service account, Deployment, and Service. The pod runs as UID 65532 with a read-only root filesystem, no capabilities, no service account token, and the `RuntimeDefault` seccomp profile. |
| `networkpolicy.yaml` | Denies all egress and allows ingress on TCP 5000 only. Your network plugin must enforce NetworkPolicy for this to do anything. |

## 1. Install Kyverno

The policy needs Kyverno 1.20 or later. Kyverno 1.20.0 ships as Helm chart 3.10.0.

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm install kyverno kyverno/kyverno --version 3.10.0 -n kyverno --create-namespace
kubectl -n kyverno rollout status deployment/kyverno-admission-controller
```

The admission controller needs outbound HTTPS to `ghcr.io`, `rekor.sigstore.dev`, and the Sigstore TUF mirror to check signatures. The network policy in this directory applies only to `defense-up`, so it doesn't block Kyverno.

## 2. Create the namespace and the policy

Apply the policy before the Deployment. A pod admitted before the policy exists never gets checked.

```bash
kubectl apply -f namespace.yaml
kubectl apply -f kyverno-image-policy.yaml
kubectl wait --for=jsonpath='{.status.conditionStatus.ready}'=true \
  imagevalidatingpolicy/defense-up-signed-releases-only --timeout=60s
```

## 3. Set the image digest

`deployment.yaml` ships with the placeholder `sha256:REPLACE_WITH_RELEASE_DIGEST`. Kyverno rejects the Deployment until you replace it.

Open the GitHub release for the version you want and copy the digest from the "Container image" section of the release notes. That digest names the multi-platform index, and it's the one the workflow signed. Don't use a per-platform digest from the table below it.

```bash
DIGEST=sha256:<digest from the release notes>
sed -i.bak "s/sha256:REPLACE_WITH_RELEASE_DIGEST/${DIGEST}/" deployment.yaml
rm deployment.yaml.bak
```

You can verify the same evidence yourself first with the `cosign verify` and `gh attestation verify` commands in the release notes.

## 4. Deploy

```bash
kubectl apply -f deployment.yaml -f networkpolicy.yaml
kubectl -n defense-up rollout status deployment/defense-up
kubectl -n defense-up port-forward service/defense-up 8080:80
```

In another terminal, `curl http://127.0.0.1:8080/healthz` returns `{"status":"ok"}`.

## Watch it block

Try to run nginx in the namespace. The pod spec below meets the `restricted` profile, so Pod Security lets it through and Kyverno makes the call. The image is pinned by digest, so the digest check passes too. The request fails because nobody signed nginx with the defense-up release workflow.

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: not-ours
  namespace: defense-up
spec:
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: nginx
      # nginx:1.29 as of 2026-11-12. Any digest works for this exercise.
      image: docker.io/library/nginx@sha256:1881968aff6f7cdcc4b888c00a11f4ce241ad7ec957e0cb4a9e19e93a3ff87ea
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
EOF
```

The API server rejects the pod with a message from `defense-up-signed-releases-only`. Running the same pod through the Kyverno CLI gives this result.

```text
Every image must carry a keyless cosign signature from onlydole/defense-up/.github/workflows/release.yml on a vX.Y.Z tag.; verification details: image "docker.io/library/nginx@sha256:1881968aff6f7cdcc4b888c00a11f4ce241ad7ec957e0cb4a9e19e93a3ff87ea", attestor "releaseWorkflow": failed to verify cosign signatures: no signatures found
```

Two more things to try.

- Change the image to `nginx:1.29`. Kyverno rejects it because the reference has no digest.
- Point the running Deployment at nginx with `kubectl -n defense-up set image deployment/defense-up web=docker.io/library/nginx@sha256:1881968aff6f7cdcc4b888c00a11f4ce241ad7ec957e0cb4a9e19e93a3ff87ea`. Kyverno checks the Deployment itself, so the update fails and the old pods keep running.

## Check a release without a cluster

The Kyverno CLI runs the same checks against a manifest on your machine. Download it from the [Kyverno releases page](https://github.com/kyverno/kyverno/releases) and use a version that matches your cluster. It pulls signatures from GHCR and Sigstore, so it needs network access but no cluster. Run it after you set the digest in step 3.

```bash
kyverno apply kyverno-image-policy.yaml --resource deployment.yaml
```

A signed release reports `pass: 1`. Anything else reports `fail` with the reason.

## What has and hasn't been tested

No v1 release exists yet, so nobody has run these manifests against a real defense-up image. Here's what was checked when they were written.

- All manifests pass `kubeconform -strict`. For the policy, kubeconform used the `ImageValidatingPolicy` schema from the Kyverno 1.20.0 CRD.
- Kyverno CLI 1.20.0 rejected nginx by digest, nginx by tag, an unsigned image, and images signed by a different GitHub workflow.
- The same policy, with the identity changed to Kyverno's own test workflow, passed a cosign v3 keyless signature and a GitHub `attest-build-provenance` attestation on GHCR. That's the closest available stand-in for a defense-up release.
- Nothing here has run in a live cluster yet. That leaves Pod Security, the NetworkPolicy, the probes, and the `/dev/shm` mount untested on a running node.
- Not tested on an image that carries both a cosign signature and a GitHub attestation, which is what the release workflow produces. Run the CLI check above on the first release.
