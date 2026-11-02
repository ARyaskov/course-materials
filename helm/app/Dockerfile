# syntax=docker/dockerfile:1.7

# --- слой сборки -----------------------------------------------------------
FROM golang:1.25-alpine AS build
WORKDIR /src

# Зависимости отдельным слоем: пока go.mod/go.sum не менялись, слой берётся из кэша
# и `go mod download` не повторяется на каждом коммите.
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download

COPY . .
ARG VERSION=dev
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -trimpath \
      -ldflags="-s -w" \
      -o /out/api ./cmd/api && \
    CGO_ENABLED=0 go build -trimpath \
      -ldflags="-s -w" \
      -o /out/worker ./cmd/worker && \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/migrate ./cmd/migrate

# --- runtime ---------------------------------------------------------------
FROM gcr.io/distroless/static-debian12:nonroot AS runtime
WORKDIR /app
COPY --from=build /out/api /app/api
COPY --from=build /out/worker /app/worker
COPY --from=build /out/migrate /app/migrate

# Непривилегированный пользователь задан в базовом образе (uid 65532).
USER nonroot:nonroot
EXPOSE 8080 9090

ARG VERSION=dev
LABEL org.opencontainers.image.title="tessera" \
      org.opencontainers.image.description="Ticket sales and validation API" \
      org.opencontainers.image.source="https://github.com/tessera-app/tessera" \
      org.opencontainers.image.version="${VERSION}"

# Форма exec: процесс становится PID 1 и получает SIGTERM напрямую,
# без промежуточного shell, который сигнал не пробрасывает.
ENTRYPOINT ["/app/api"]
