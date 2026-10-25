# Alert service image (research R4). Build context is the repository root, so the service can
# depend on Packages/AuroraCore by path:
#   docker build -f Server/Dockerfile -t revontulet-alerts .
# Built by GitHub Actions for linux/amd64; never built on the server.

# ---- Build -------------------------------------------------------------------------------------
FROM swift:6.4.1-noble AS build

WORKDIR /build
COPY Packages/AuroraCore Packages/AuroraCore
COPY Server/Package.swift Server/Package.resolved Server/
RUN swift package resolve --package-path Server
COPY Server Server

RUN swift build -c release --static-swift-stdlib --package-path Server \
    && mkdir /staging \
    && BIN="$(swift build -c release --package-path Server --show-bin-path)" \
    && cp "$BIN/alert-service" /staging/ \
    && find -L "$BIN/" -maxdepth 1 -regex '.*\.\(resources\|bundle\)$' -exec cp -Ra {} /staging/ \; \
    && cp /usr/libexec/swift/linux/swift-backtrace-static /staging/swift-backtrace

# ---- Run ---------------------------------------------------------------------------------------
FROM ubuntu:noble

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --user-group --create-home --system --home-dir /app alerts \
    && mkdir /data && chown alerts:alerts /data

WORKDIR /app
COPY --from=build --chown=alerts:alerts /staging /app

# Crash backtraces go to stderr; no request data is ever logged.
ENV SWIFT_BACKTRACE=enable=yes,sanitize=yes,threads=all,images=all,interactive=no,swift-backtrace=./swift-backtrace

USER alerts:alerts
EXPOSE 8080

HEALTHCHECK --interval=60s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8080/v1/health > /dev/null || exit 1

ENTRYPOINT ["./alert-service"]
