#!/usr/bin/env bash
# Generates a self-signed certificate for LOCAL DEVELOPMENT ONLY.
# Production must use a CA-issued certificate (Let's Encrypt or internal military CA).
set -euo pipefail

# Git Bash on Windows rewrites /C=EG/... in the OpenSSL -subj argument into a
# Windows path (C:/Program Files/Git/C=EG/...), which OpenSSL rejects. Disable
# MSYS path conversion for this script. Harmless on Linux/macOS.
export MSYS_NO_PATHCONV=1

SSL_DIR="$(dirname "$0")/../nginx/ssl"
mkdir -p "$SSL_DIR"

openssl req -x509 -nodes -newkey ec \
  -pkeyopt ec_paramgen_curve:prime256v1 \
  -keyout "$SSL_DIR/server.key" \
  -out "$SSL_DIR/server.crt" \
  -days 365 \
  -subj "/C=EG/O=IronLink/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

chmod 600 "$SSL_DIR/server.key"
echo "Self-signed cert written to $SSL_DIR (dev only — replace for production)"
