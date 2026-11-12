## What changed

<!-- One or two sentences on the change and why it's needed. -->

## How I tested it

<!-- Commands you ran and what they showed. -->

## Checklist

- [ ] Every new or changed `uses:` line pins a full commit SHA with the version in a comment.
- [ ] New jobs start from `permissions: {}` and ask only for the scopes they need.
- [ ] Base images are pinned by digest, and `requirements.txt` was regenerated with hashes if `requirements.in` changed.
- [ ] The README and `docs/threat-model.md` still describe what the pipeline does.
- [ ] No plans, specs, or generated artifacts are in the diff.
