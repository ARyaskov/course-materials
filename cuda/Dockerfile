# Многостадийная сборка veclens.
#
# Стадия builder содержит полный CUDA Toolkit (nvcc, NVRTC, заголовки CUB,
# Nsight-инструменты) — это несколько гигабайт, которые в рантайме не нужны.
# Стадия runtime несёт только разделяемые библиотеки CUDA и собранные
# бинарники, поэтому итоговый образ меньше в разы.
#
# Сборка:
#   docker build -t veclens:1.0 .
#   docker build -t veclens:1.0 --build-arg CUDA_ARCHS="86" .
#
# Запуск (нужен nvidia-container-toolkit на хосте, иначе внутри контейнера
# не будет ни /dev/nvidia*, ни драйверных библиотек):
#   docker run --rm --gpus all veclens:1.0 device-info
#   docker run --rm --gpus '"device=0"' -v "$PWD/data:/data" veclens:1.0 \
#       search --index /data/index.vlx --queries /data/queries.fvecs
#
# Драйвер в образ не входит принципиально: он приходит с хоста через
# nvidia-container-toolkit. Версия CUDA в образе может быть новее драйвера
# только в пределах minor version compatibility.

# ------------------------------------------------------------------ builder
FROM nvidia/cuda:13.0.0-devel-ubuntu24.04 AS builder

ARG CUDA_ARCHS="75;86;89;90"
ARG BUILD_TYPE=Release
ARG JOBS=

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        ninja-build \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Сначала только описание сборки: слой с apt и конфигурацией CMake не будет
# пересобираться при каждом изменении исходников.
COPY CMakeLists.txt ./
COPY cmake ./cmake

COPY include ./include
COPY src ./src
COPY apps ./apps
COPY tests ./tests
COPY bench ./bench

RUN cmake -S . -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
        -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCHS}" \
        -DCMAKE_INSTALL_PREFIX=/opt/veclens \
        -DVECLENS_BUILD_TESTS=ON \
        -DVECLENS_BUILD_BENCH=ON \
    && cmake --build build ${JOBS:+-j ${JOBS}} \
    && cmake --install build

# Микробенчмарки ставятся отдельно: install() в CMakeLists их не перечисляет,
# а в образе они полезны для быстрой проверки карты.
RUN mkdir -p /opt/veclens/bin \
    && cp build/bench_stride build/bench_distance build/bench_topk \
          build/bench_p2p build/bench_end_to_end /opt/veclens/bin/ \
    && cp build/test_buffers build/test_topk build/test_ivf /opt/veclens/bin/

# ------------------------------------------------------------------ runtime
FROM nvidia/cuda:13.0.0-runtime-ubuntu24.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive

# python3 нужен только для scripts/bench_report.py; внешних пакетов у него нет.
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3-minimal \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/veclens /opt/veclens
COPY scripts/bench_report.py /opt/veclens/scripts/bench_report.py

ENV PATH="/opt/veclens/bin:${PATH}" \
    LD_LIBRARY_PATH="/opt/veclens/lib:${LD_LIBRARY_PATH}"

# Каталог для данных и индексов; в проде монтируется томом.
VOLUME ["/data"]
WORKDIR /data

# Контейнер запускается не от root: движку хватает прав на чтение /data.
RUN useradd --create-home --uid 10001 veclens && chown veclens:veclens /data
USER veclens

# Проверка живости: карта видна и рантайм CUDA инициализируется.
HEALTHCHECK --interval=60s --timeout=10s --retries=3 \
    CMD veclens device-info >/dev/null || exit 1

ENTRYPOINT ["veclens"]
CMD ["device-info"]
