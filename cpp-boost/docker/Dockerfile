# Multi-stage build.
# Stage 1 builds Boost 1.92 from source with b2 (distribution packages lag behind: Rota needs
# Boost.Parser, Hash2 and Cobalt, which are not in Debian's 1.88) and then Rota itself.
# Stage 2 is a slim runtime image with the two binaries, the plugin and the configs.

FROM debian:trixie AS boost
ARG BOOST_VERSION=1.92.0
RUN apt-get update && apt-get install -y --no-install-recommends \
        g++ curl ca-certificates libssl-dev zlib1g-dev libbz2-dev libzstd-dev liblzma-dev python3 python-is-python3 && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /opt
RUN set -eux; \
    v_underscore="$(echo ${BOOST_VERSION} | tr . _)"; \
    curl -fsSL "https://archives.boost.io/release/${BOOST_VERSION}/source/boost_${v_underscore}.tar.gz" | tar xz; \
    cd "boost_${v_underscore}"; \
    ./bootstrap.sh --prefix=/opt/boost; \
    ./b2 -j"$(nproc)" install link=static runtime-link=shared variant=release cxxstd=23 \
        --with-system --with-json --with-url --with-log --with-program_options --with-serialization \
        --with-filesystem --with-iostreams --with-thread --with-atomic --with-charconv --with-cobalt \
        --with-process --with-locale --with-date_time --with-container --with-stacktrace --with-test \
        --with-context --with-chrono --with-random --with-exception

FROM boost AS build
RUN apt-get update && apt-get install -y --no-install-recommends cmake ninja-build && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY . .
RUN cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=/opt/boost \
        -DROTA_STATIC_BOOST=ON -DROTA_BUILD_TESTS=ON -DROTA_WITH_REDIS=ON -DROTA_WITH_MYSQL=ON && \
    cmake --build build && \
    ctest --test-dir build --output-on-failure --timeout 60

FROM debian:trixie
RUN apt-get update && apt-get install -y --no-install-recommends libssl3t64 zlib1g libbz2-1.0 libzstd1 liblzma5 curl tzdata python3 python-is-python3 ca-certificates && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /rota
COPY --from=build /src/build/apps/rotad/rotad /usr/local/bin/rotad
COPY --from=build /src/build/apps/rota-cli/rota /usr/local/bin/rota
COPY --from=build /src/build/plugins/echo_executor/echo_executor.so /rota/plugins/echo_executor.so
COPY config/rota.docker.json /rota/config/rota.json
COPY pipelines/nightly-report.json /rota/pipelines/nightly-report.json
COPY pipelines/smoke.linux.json.example /rota/pipelines/smoke.json
COPY scripts/ /rota/scripts/
EXPOSE 8080 8081
HEALTHCHECK --interval=10s --timeout=3s CMD curl -fs http://127.0.0.1:8080/api/v1/health || exit 1
ENTRYPOINT ["rotad", "--config", "/rota/config/rota.json"]
