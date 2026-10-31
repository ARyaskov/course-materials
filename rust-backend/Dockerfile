# syntax=docker/dockerfile:1.7
# Multi-stage build with cargo-chef: dependencies are compiled in a layer that
# only changes when Cargo.toml/Cargo.lock change, so code edits rebuild in
# seconds instead of minutes.

ARG RUST_VERSION=1.98
FROM rust:${RUST_VERSION}-bookworm AS chef
RUN cargo install cargo-chef --locked
WORKDIR /app

FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder
COPY --from=planner /app/recipe.json recipe.json
# Dependencies only: cached until the manifests change.
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    cargo chef cook --release --workspace --recipe-path recipe.json
COPY . .
# No database at build time: query!() reads the checked-in .sqlx/ metadata.
ENV SQLX_OFFLINE=true
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    cargo build --release --workspace --bins

FROM debian:bookworm-slim AS runtime-base
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 --create-home courseflow
USER courseflow
WORKDIR /home/courseflow
ENV COURSEFLOW_LOG_FORMAT=json RUST_LOG=info

FROM runtime-base AS api
COPY --from=builder /app/target/release/courseflow-api /usr/local/bin/courseflow-api
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8080/health/live || exit 1
ENTRYPOINT ["courseflow-api"]

FROM runtime-base AS worker
COPY --from=builder /app/target/release/courseflow-worker /usr/local/bin/courseflow-worker
EXPOSE 8081
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8081/health/live || exit 1
ENTRYPOINT ["courseflow-worker"]

FROM runtime-base AS billing-mock
COPY --from=builder /app/target/release/billing-mock /usr/local/bin/billing-mock
EXPOSE 8090
ENTRYPOINT ["billing-mock"]
