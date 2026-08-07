FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# ── Dependency layer (cached unless requirements change) ────────────────────
FROM base AS deps
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ── Runtime image ─────────────────────────────────────────────────────────
FROM deps AS runtime
# Install Tesseract OCR and language packs
RUN apt-get update && apt-get install -y \
    tesseract-ocr \
    libtesseract-dev \
    tesseract-ocr-eng \
    tesseract-ocr-ara \
    && rm -rf /var/lib/apt/lists/*

COPY . .

# chmod +x explicitly: the executable bit does not survive a clone from a
# Windows working tree, so relying on the committed mode would break the build.
RUN chmod +x /app/docker-entrypoint.sh

# Non-root user for principle of least privilege
RUN addgroup --system ironlink && adduser --system --ingroup ironlink mil_api
USER mil_api

EXPOSE 8000

# The entrypoint applies migrations and then execs uvicorn. It reads $PORT at
# runtime, because Render and most PaaS inject the listening port and will not
# route to a hardcoded one. WEB_CONCURRENCY defaults to 1: this previously ran
# 4 workers, which on a 512 MB instance means four interpreters plus four Redis
# pools and an OOM kill. Raise it only alongside the instance size.
CMD ["/app/docker-entrypoint.sh"]