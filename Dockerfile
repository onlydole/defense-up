# Both stages use the same Chainguard Python build, so the packages the builder
# installs match the interpreter the runtime ships. Each image is pinned by
# digest so a rebuild can't silently pick up a different base. The tag stays
# for readability and so Dependabot can propose digest bumps.

# Builder: has pip and a shell. Nothing from this stage ships except the
# installed packages.
FROM cgr.dev/chainguard/python:latest-dev@sha256:bfa57b0e812295420c4839d30be0868d4a466ed3c6fed009cd0b5f82bb7e88fd AS builder

WORKDIR /app

COPY requirements.txt .

# --require-hashes rejects any file whose hash isn't in requirements.txt.
# --only-binary=:all: refuses source builds, so no package runs build code here.
RUN pip install --target=/app/packages --no-cache-dir --require-hashes \
    --only-binary=:all: \
    --disable-pip-version-check \
    --no-compile \
    -r requirements.txt

# Test: runs the unit tests against the same locked packages the runtime gets.
# Build it with `docker build --target test .`. A normal build skips this
# stage, and nothing from it ships.
FROM builder AS test

COPY app/ /app/app/
COPY tests/ /app/tests/

RUN PYTHONPATH=/app/packages PYTHONDONTWRITEBYTECODE=1 \
    python -m unittest discover --start-directory tests --top-level-directory . --verbose

# Runtime: no shell, no package manager, and a non-root user by default.
FROM cgr.dev/chainguard/python:latest@sha256:872a42d369a6d9efba17ff4ccf4c0ec103b9e511e5f77793b0f558b933e40929

WORKDIR /app

# Copy only what the app needs: the installed packages and the app source.
COPY --from=builder /app/packages /app/packages
COPY app/ /app/app/

ENV PYTHONPATH=/app/packages \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# 65532 is the nonroot user in Chainguard images. Setting it here makes the
# choice visible instead of relying on the base image default.
USER 65532:65532

EXPOSE 5000

# The image has no shell or curl, so the check uses the Python it already ships.
# Docker and Compose honor this. Kubernetes ignores it and uses its own probes.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/usr/bin/python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/healthz', timeout=2)"]

# Serve with gunicorn, a production WSGI server, instead of Flask's dev server.
# --worker-tmp-dir /dev/shm keeps gunicorn's heartbeat files in memory, so the
# container runs with a read-only root filesystem.
ENTRYPOINT ["/usr/bin/python", "-m", "gunicorn"]
CMD ["--bind", "0.0.0.0:5000", "--worker-tmp-dir", "/dev/shm", "--access-logfile", "-", "app.main:app"]
