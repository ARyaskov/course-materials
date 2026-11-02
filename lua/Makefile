# sift — сборка, тесты, демонстрация.
#
#   make test       прогнать тесты
#   make sample     сгенерировать демонстрационный лог
#   make report     текстовый отчёт по демонстрационному логу
#   make html       HTML-отчёт в build/report.html
#   make json       JSON-отчёт в build/report.json
#   make index      построить и показать бинарный индекс
#   make native     собрать необязательный C-модуль
#   make bench      замер пропускной способности
#   make check      всё, что должно проходить перед коммитом
#   make clean      убрать сгенерированное

LUA        ?= lua
LUA_INCDIR ?= /usr/include/lua5.5
EVENTS     ?= 200000
SAMPLE      = data/sample.ndjson
CONFIG      = etc/sift.conf.lua
REPORT      = ./bin/sift report --config $(CONFIG)

# sift возвращает 3, когда цели SLO нарушены. Для сборки это штатный исход:
# демонстрационные данные содержат два инцидента, и цели там нарушены всегда.
# А вот 1 (ошибка выполнения) и 2 (ошибка аргументов) — настоящие сбои.
# Глушить префиксом `-` все коды подряд нельзя: тогда make печатает «пройдено»
# поверх сломанного инструмента.
OK_OR_SLO = rc=$$?; [ $$rc -eq 0 ] || [ $$rc -eq 3 ] || exit $$rc

.PHONY: test sample report html json index native bench check check-rockspec clean

test:
	$(LUA) test/all.lua

$(SAMPLE):
	mkdir -p "$(@D)"
	$(LUA) scripts/gen-sample.lua --events $(EVENTS) --out $(SAMPLE)

sample: $(SAMPLE)

report: $(SAMPLE)
	@$(REPORT); $(OK_OR_SLO)

html: $(SAMPLE) build
	@$(REPORT) --format html -o build/report.html; $(OK_OR_SLO); \
	 echo "отчёт: build/report.html"

json: $(SAMPLE) build
	@$(REPORT) --format json -o build/report.json; $(OK_OR_SLO); \
	 echo "отчёт: build/report.json"

index: $(SAMPLE)
	./bin/sift index build $(SAMPLE)
	./bin/sift index info $(SAMPLE)

build:
	mkdir -p build

native:
	$(MAKE) -C csrc LUA_INCDIR=$(LUA_INCDIR)

bench:
	./bin/sift bench --events $(EVENTS)

check-rockspec:
	$(LUA) scripts/check-rockspec.lua

# Зависимость от $(SAMPLE) обязательна: без неё после make clean проверка
# читала бы несуществующий файл и всё равно объявляла себя пройденной.
check: test check-rockspec $(SAMPLE)
	@$(REPORT) >/dev/null; rc=$$?; \
	 if [ $$rc -ne 0 ] && [ $$rc -ne 3 ]; then \
	   echo "отчёт завершился с кодом $$rc" >&2; exit $$rc; \
	 fi; \
	 echo "проверки пройдены"

clean:
	rm -rf build $(SAMPLE) $(SAMPLE).sidx sift_native.so
