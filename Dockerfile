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

# Non-root user for principle of least privilege
RUN addgroup --system ironlink && adduser --system --ingroup ironlink mil_api
USER mil_api

EXPOSE 8000

# Render (and most PaaS) inject the listening port as $PORT and will not route
# to a hardcoded one, so it has to be read at runtime — hence the sh -c form.
# `exec` hands PID 1 to uvicorn so SIGTERM reaches it and shutdown stays
# graceful instead of being killed after the grace period.
#
# WEB_CONCURRENCY defaults to 1: this previously ran 4 workers, which on a
# 512 MB instance means four copies of the interpreter plus four Redis pools
# and an OOM kill. Raise it only alongside the instance size.
CMD ["sh", "-c", "exec uvicorn app.main:app \
     --host 0.0.0.0 \
     --port ${PORT:-8000} \
     --workers ${WEB_CONCURRENCY:-1} \
     --loop uvloop \
     --http h11 \
     --proxy-headers \
     --forwarded-allow-ips '*'"]