# Both stages use the same Chainguard Python build, so the packages the builder
# installs match the interpreter the runtime ships. Each image is pinned by
# digest so a rebuild can't silently pick up a different base. The tag stays
# for readability and so Dependabot can propose digest bumps.

# Builder: has pip and a shell. Nothing from this stage ships except the
# installed packages.
FROM cgr.dev/chainguard/python:latest-dev@sha256:62c16c709c48c8e66647c843b5aceeac81d4523134c742bc017a46f5a86ba5dd AS builder

WORKDIR /app

COPY requirements.txt .

# --require-hashes rejects any file whose hash isn't in requirements.txt.
# --only-binary=:all: refuses source builds, so no package runs build code here.
RUN pip install --target=/app/packages --no-cache-dir --require-hashes \
    --only-binary=:all: \
    --disable-pip-version-check \
    --no-compile \
    -r requirements.txt

# Runtime: no shell, no package manager, and a non-root user by default.
FROM cgr.dev/chainguard/python:latest@sha256:c932048a3f1db1fecefbd589d4fb90bf1d364b4c1ebd9aa8c866f29bb93e88cc

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

# Serve with gunicorn, a production WSGI server, instead of Flask's dev server.
ENTRYPOINT ["/usr/bin/python", "-m", "gunicorn"]
CMD ["--bind", "0.0.0.0:5000", "--access-logfile", "-", "app.main:app"]
