#!/usr/bin/env bash
# Проверка направления зависимостей между слоями.
#
# Договорённость об архитектуре, которую никто не проверяет, живёт
# ровно до первого срочного исправления. Этот скрипт запускается
# в конвейере сборки рядом с тестами.
#
# Правило одно: зависимости направлены внутрь.
#   domain        ← ничего внешнего
#   repositories  ← domain
#   services      ← domain, repositories
#   api, jobs     ← всё выше
#   infrastructure реализует протоколы из services, но services про неё не знает

set -euo pipefail

SRC="src/depot"
status=0

check() {
    local layer="$1" pattern="$2" message="$3"
    if grep -rnE "$pattern" "$SRC/$layer" --include='*.py' >/tmp/layer_violations 2>/dev/null; then
        echo "НАРУШЕНИЕ: $message"
        sed 's/^/  /' /tmp/layer_violations
        status=1
    fi
}

# Домен не знает ни про веб-фреймворк, ни про базу, ни про сеть.
# Именно это позволяет проверять правила аренды без запуска приложения.
check domain \
    '^\s*(from|import)\s+(flask|sqlalchemy|redis|httpx|boto3|rq)\b' \
    "домен зависит от внешней библиотеки"

check domain \
    '^\s*from\s+depot\.(api|services|repositories|infrastructure|jobs)\b' \
    "домен зависит от внешнего слоя"

# Репозитории работают с базой, но не знают о сценариях и о HTTP.
check repositories \
    '^\s*from\s+depot\.(api|jobs|infrastructure)\b' \
    "репозиторий зависит от внешнего слоя"

check repositories \
    '^\s*(from|import)\s+flask\b' \
    "репозиторий зависит от веб-фреймворка"

# Сервисы объявляют протоколы, а не импортируют реализации: подстановка
# заглушки в тесте не должна требовать Redis.
check services \
    '^\s*from\s+depot\.(api|jobs|infrastructure)\b' \
    "сервис зависит от реализации вместо протокола"

check services \
    '^\s*(from|import)\s+(flask|redis|boto3|rq)\b' \
    "сервис зависит от инструмента напрямую"

# Инфраструктура не должна тянуть за собой контекст запроса: тот же
# код работает в воркере, где никакого запроса нет.
check infrastructure \
    '^\s*from\s+flask\s+import\s+.*\b(request|g|session)\b' \
    "инфраструктура использует контекст запроса"

if [ "$status" -eq 0 ]; then
    echo "слои в порядке"
fi

exit "$status"
