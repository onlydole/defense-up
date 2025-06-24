FROM cgr.dev/chainguard/python:latest-dev AS builder

WORKDIR /app

COPY requirements.txt .
RUN pip install --target=/app/packages --no-cache-dir --require-hashes \
    --disable-pip-version-check \
    --no-compile \
    -r requirements.txt

COPY . .

FROM gcr.io/distroless/python3-debian12:nonroot

COPY --from=builder /app /app

WORKDIR /app
EXPOSE 5000
ENV PYTHONPATH=/app/packages
CMD ["app/main.py"]