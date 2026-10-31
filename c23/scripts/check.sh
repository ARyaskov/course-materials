#!/usr/bin/env bash
# Полная проверка проекта: сборка обоими компиляторами, тесты,
# санитайзеры, статический анализ. Одна команда перед коммитом.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
step() { printf '\n=== %s ===\n' "$1"; }

step "Проверка тулчейна"
for cc in gcc clang; do
    if command -v "$cc" >/dev/null 2>&1; then
        printf '%-8s %s\n' "$cc" "$("$cc" --version | head -1)"
        echo 'int main(void){ return __STDC_VERSION__ == 202311L ? 0 : 1; }' > /tmp/nst-c23.c
        if "$cc" -std=c23 /tmp/nst-c23.c -o /tmp/nst-c23 2>/dev/null && /tmp/nst-c23; then
            echo "  режим C23: доступен"
        else
            echo "  режим C23: НЕ доступен"; fail=1
        fi
    else
        echo "$cc: не найден (пропускаем)"
    fi
done
rm -f /tmp/nst-c23 /tmp/nst-c23.c

step "Сборка и тесты (make, gcc)"
make clean >/dev/null
make -j"$(nproc)" test || fail=1

step "ASan + UBSan"
make asan || fail=1

step "ThreadSanitizer"
make tsan || fail=1

if command -v clang >/dev/null 2>&1; then
    step "Сборка clang"
    make clean >/dev/null
    make -j"$(nproc)" test CC=clang || fail=1
fi

step "Статический анализ (gcc -fanalyzer)"
make clean >/dev/null
make -j"$(nproc)" OPT="-O2 -fanalyzer" 2>&1 | grep -E 'warning|analyzer' || echo "замечаний нет"

step "Сквозная проверка сервера"
./scripts/smoke.sh || fail=1

make clean >/dev/null
if [ "$fail" -eq 0 ]; then
    echo -e "\nВсе проверки пройдены."
else
    echo -e "\nЕсть провалы, см. вывод выше." >&2
fi
exit "$fail"
