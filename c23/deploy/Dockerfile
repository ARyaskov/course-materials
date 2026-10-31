# Многоступенчатая сборка: компилятор не попадает в итоговый образ.
FROM debian:trixie-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc cmake make libc6-dev ca-certificates && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY . .
RUN cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo -DNESTOR_LTO=ON && \
    cmake --build build -j"$(nproc)" && \
    ctest --test-dir build --output-on-failure

FROM debian:trixie-slim
RUN groupadd -r nestor && useradd -r -g nestor -d /var/lib/nestor nestor && \
    mkdir -p /var/lib/nestor && chown nestor:nestor /var/lib/nestor
COPY --from=build /src/build/nestord /src/build/nestor-cli /usr/local/bin/
USER nestor
VOLUME /var/lib/nestor
EXPOSE 7717
HEALTHCHECK --interval=10s --timeout=2s --retries=3 \
    CMD nestor-cli --port 7717 ping | grep -q PONG
ENTRYPOINT ["/usr/local/bin/nestord", "--dir", "/var/lib/nestor", "--port", "7717"]
