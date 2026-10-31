#!/usr/bin/env bash
# Сборка и запуск фаззеров (нужен clang с libFuzzer).
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="${1:-proto}"
SECONDS_TO_RUN="${2:-60}"
mkdir -p build/fuzz "corpus/$TARGET"

case "$TARGET" in
    proto)  EXTRA="src/net/proto.c" ;;
    record) EXTRA="src/store/record.c" ;;
    *) echo "использование: $0 [proto|record] [секунды]" >&2; exit 2 ;;
esac

clang -std=c23 -g -O1 -fsanitize=fuzzer,address,undefined \
      -Iinclude -Isrc \
      "fuzz/fuzz_$TARGET.c" $EXTRA src/util/slice.c src/util/buf.c \
      src/util/crc32c.c src/util/status.c \
      -o "build/fuzz/fuzz_$TARGET"

"./build/fuzz/fuzz_$TARGET" "corpus/$TARGET" \
    -max_total_time="$SECONDS_TO_RUN" -print_final_stats=1
