# GLM Bridge (Z.AI proxy) — server image.
#
# Build:  docker build -t zai-api .
# Run:    docker run -d --name zai-api -p 3001:3001 \
#             -e AUTH_TOKEN=change-me \
#             -e ZAI_TOKEN=<optional jwt> \
#             -v zai-data:/data \
#             zai-api
#
# Notes:
# - Server-only image. The token collector (cmd/token-collector) needs a
#   browser + Playwright and is intentionally NOT built here — harvest
#   tokens.sqlite locally, then mount it at /data/tokens.sqlite or hot-swap
#   it into the running server via POST /sqlite (no restart needed).
# - Pure-Go SQLite (modernc.org/sqlite, no CGO), so the binary is fully
#   static and runs on the tiny Alpine final image.
# - Floating `1-alpine` / `3` tags track the latest lightweight releases;
#   pin exact versions (e.g. golang:1.25-alpine, alpine:3.22) for
#   reproducible production builds.

# ── Builder ──────────────────────────────────────────────────────────────
FROM golang:1-alpine AS builder

RUN apk add --no-cache git

WORKDIR /src

# The repo ships without go.mod by design (see README step 2), so init it
# when absent (e.g. a clean git clone as the build context).
COPY . .
RUN if [ ! -f go.mod ]; then go mod init zai-api; fi \
    && go mod tidy \
    && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/zai-api .

# ── Runtime ──────────────────────────────────────────────────────────────
FROM alpine:3

RUN apk add --no-cache ca-certificates \
    && adduser -D -h /home/app app \
    && mkdir -p /data && chown app:app /data

COPY --from=builder /out/zai-api /usr/local/bin/zai-api

USER app
WORKDIR /home/app

# Server configuration. Override at run time (-e / compose / .env).
# AUTH_TOKEN has no safe default baked in — compose generates/passes it.
ENV PORT=3001 \
    HOST=0.0.0.0 \
    AGENT_MODE=true

EXPOSE 3001
VOLUME ["/data"]

# BusyBox wget ships with Alpine — no extra client needed for the probe.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD wget -qO- "http://localhost:${PORT:-3001}/health" > /dev/null || exit 1

# Exec form so SIGTERM reaches Go (graceful drain + session cleanup).
ENTRYPOINT ["zai-api"]
CMD ["--db-path=/data/tokens.sqlite"]
