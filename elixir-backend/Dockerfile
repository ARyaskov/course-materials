# Многостадийная сборка: в финальном образе нет ни Elixir, ни исходников —
# только релиз и рантайм Erlang, собранный внутрь релиза.
FROM hexpm/elixir:1.20.0-erlang-28.5.0.2-debian-trixie-20260610-slim AS base

RUN apt-get update && apt-get install -y --no-install-recommends build-essential git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

RUN mix local.hex --force && mix local.rebar --force

FROM base AS build
ENV MIX_ENV=prod

# Зависимости отдельным слоем: пересобираются только при изменении mix.exs/mix.lock.
COPY mix.exs mix.lock ./
COPY config/config.exs config/prod.exs config/
RUN mix deps.get --only prod --check-locked && mix deps.compile

COPY priv priv
COPY assets assets
COPY lib lib
RUN mix assets.setup && mix assets.deploy && mix compile --warnings-as-errors

COPY config/runtime.exs config/
COPY rel rel
RUN chmod +x rel/overlays/bin/migrate && mix release

FROM base AS check
ENV MIX_ENV=test
COPY mix.exs mix.lock .formatter.exs .credo.exs .sobelow-conf .dialyzer_ignore.exs coveralls.json ./
COPY config config
RUN mix deps.get --check-locked && mix deps.compile
COPY lib lib
COPY test test
COPY priv priv
COPY bench bench
COPY assets assets
CMD ["mix", "check"]

FROM debian:trixie-slim AS app

RUN apt-get update && apt-get install -y --no-install-recommends libstdc++6 libncurses6 libssl3t64 ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --create-home --home-dir /app klaxon

WORKDIR /app
USER klaxon

ENV LANG=C.UTF-8 \
    HOME=/app \
    MIX_ENV=prod \
    PHX_SERVER=true

COPY --from=build --chown=klaxon:klaxon /src/_build/prod/rel/klaxon ./

EXPOSE 4000

# exec-форма: сигналы ОС доходят до релиза напрямую, без прослойки shell.
ENTRYPOINT ["/app/bin/klaxon"]
CMD ["start"]
