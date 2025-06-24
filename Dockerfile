FROM python:3.13-slim AS builder

WORKDIR /src

COPY requirements.txt .
RUN pip install --upgrade pip \
    && pip install --prefix=/install --no-cache-dir -r requirements.txt

COPY app/ ./app

FROM python:3.13-slim

RUN useradd --create-home --shell /bin/bash flaskuser

COPY --from=builder /install /usr/local
COPY --from=builder /src/app /app

EXPOSE 5000

USER flaskuser

WORKDIR /app

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "main:app"]