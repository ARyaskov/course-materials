# Многоэтапная сборка: инструменты компиляции нужны при установке
# зависимостей и не нужны в работающем контейнере. Разделение убирает
# из итогового образа компилятор, заголовки и кеш пакетов — это и размер,
# и заметно меньшая поверхность атаки.

# Тег с цифрой исправления, а не «3.15»: плавающий тег означает, что
# сборка сегодня и через месяц дают разные образы.
FROM python:3.15.0-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Слой с системными пакетами меняется реже слоя с зависимостями Python,
# поэтому он идёт первым и переиспользуется при пересборке.
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Виртуальное окружение целиком копируется в финальный образ одним слоем.
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Сначала только файл с зависимостями: слой пересобирается лишь при его
# изменении, а не при каждой правке исходников.
COPY requirements.lock.txt ./
RUN pip install --only-binary=:all: --require-hashes -r requirements.lock.txt

COPY pyproject.toml README.md ./
COPY src ./src
RUN pip install --no-deps . && pip check


FROM python:3.15.0-slim AS runtime

# Пользователь без прав администратора: процесс в контейнере не должен
# работать от root, даже если контейнер кажется изолированным.
RUN groupadd --gid 1000 depot \
    && useradd --uid 1000 --gid depot --create-home depot \
    && apt-get update \
    && apt-get install -y --no-install-recommends libpq5 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/venv /opt/venv

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONFAULTHANDLER=1

WORKDIR /app
COPY --chown=depot:depot gunicorn.conf.py wsgi.py ./
COPY --chown=depot:depot migrations ./migrations

# Версия сборки приходит аргументом: вычислить её внутри контейнера нельзя,
# репозитория там нет.
ARG BUILD_VERSION=dev
ARG BUILD_COMMIT=unknown
ARG BUILD_TIME=unknown
ENV DEPOT_BUILD_VERSION=$BUILD_VERSION \
    DEPOT_BUILD_COMMIT=$BUILD_COMMIT \
    DEPOT_BUILD_TIME=$BUILD_TIME

# Секретов здесь нет и быть не может: ENV попадает в метаданные образа
# и виден любому, кто может его скачать. Строки подключения и ключи
# передаются переменными окружения при запуске.

USER depot
EXPOSE 8000

# Проверка живости, а не готовности: контейнеру важно, жив ли процесс.
# Зависимости проверяет оркестратор отдельным вызовом /readyz.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz').read()"

# Форма exec, а не shell: процесс получает PID 1 и, главное, получает
# сигнал SIGTERM при остановке. В форме shell сигнал уходит оболочке,
# и контейнер убивают по таймауту вместе с текущими запросами.
CMD ["gunicorn", "--config", "gunicorn.conf.py", "wsgi:app"]
