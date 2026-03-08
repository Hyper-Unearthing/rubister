#!/bin/bash
set -e

# ── Clone / pull llm_gateway ─────────────────────────────────────────────────
if [ -d /app/llm_gateway/.git ]; then
  echo "[entrypoint] Pulling llm_gateway..."
  git -C /app/llm_gateway pull --ff-only
else
  echo "[entrypoint] Cloning llm_gateway..."
  git clone https://github.com/Hyper-Unearthing/llm_gateway.git /app/llm_gateway
fi

# ── Clone / pull rubister ────────────────────────────────────────────────────
if [ -d /app/rubister/.git ]; then
  echo "[entrypoint] Pulling rubister..."
  git -C /app/rubister pull --ff-only
else
  echo "[entrypoint] Cloning rubister..."
  git clone https://github.com/Hyper-Unearthing/rubister.git /app/rubister
fi

# ── Install gems ─────────────────────────────────────────────────────────────
cd /app/rubister
echo "[entrypoint] Running bundle install..."
bundle install --quiet

# ── Run ──────────────────────────────────────────────────────────────────────
exec "$@"
