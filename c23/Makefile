# Рукописная сборка nestor. Основной путь — CMake (см. CMakeLists.txt),
# этот Makefile показывает ту же сборку без генератора и используется
# в главе про make.

CC      ?= gcc
STD     := -std=c23
WARN    := -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wsign-conversion \
           -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wvla
OPT     ?= -O2
DEBUG   := -g3 -fno-omit-frame-pointer
CFLAGS  += $(STD) $(WARN) $(OPT) $(DEBUG) -Iinclude -Isrc -MMD -MP
LDFLAGS +=
LDLIBS  := -pthread

BUILD   := build
LIB_SRC := $(wildcard src/util/*.c) $(wildcard src/store/*.c) $(wildcard src/net/*.c)
LIB_OBJ := $(LIB_SRC:%.c=$(BUILD)/%.o)
TEST_SRC:= $(wildcard tests/*.c)
TEST_OBJ:= $(TEST_SRC:%.c=$(BUILD)/%.o)

BINS    := $(BUILD)/nestord $(BUILD)/nestor-cli $(BUILD)/nestor-bench
LIB     := $(BUILD)/libnestor.a

.PHONY: all clean test asan tsan bench install
all: $(LIB) $(BINS)

$(LIB): $(LIB_OBJ)
	@mkdir -p $(dir $@)
	$(AR) rcs $@ $^

$(BUILD)/nestord: $(BUILD)/src/cmd/nestord.o $(LIB)
	$(CC) $(LDFLAGS) $^ $(LDLIBS) -o $@

$(BUILD)/nestor-cli: $(BUILD)/src/cmd/nestor_cli.o $(LIB)
	$(CC) $(LDFLAGS) $^ $(LDLIBS) -o $@

$(BUILD)/nestor-bench: $(BUILD)/src/cmd/nestor_bench.o $(LIB)
	$(CC) $(LDFLAGS) $^ $(LDLIBS) -o $@

$(BUILD)/nestor-tests: $(TEST_OBJ) $(LIB)
	$(CC) $(LDFLAGS) $^ $(LDLIBS) -o $@

# Шаблонное правило: один рецепт на все объектные файлы.
$(BUILD)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -Itests -c $< -o $@

test: $(BUILD)/nestor-tests
	$(BUILD)/nestor-tests

SAN := -fsanitize=address,undefined -fno-sanitize-recover=all

asan:
	$(MAKE) clean
	$(MAKE) test OPT="-O1 $(SAN)" LDFLAGS="$(SAN)"

tsan:
	$(MAKE) clean
	$(MAKE) test OPT="-O1 -fsanitize=thread" LDFLAGS="-fsanitize=thread"

bench: $(BUILD)/nestor-bench
	$(BUILD)/nestor-bench --dir /tmp/nestor-bench --ops 200000 --threads 4

install: all
	install -d $(DESTDIR)/usr/local/bin $(DESTDIR)/usr/local/lib $(DESTDIR)/usr/local/include/nestor
	install -m 0755 $(BINS) $(DESTDIR)/usr/local/bin/
	install -m 0644 $(LIB) $(DESTDIR)/usr/local/lib/
	install -m 0644 include/nestor/*.h $(DESTDIR)/usr/local/include/nestor/

clean:
	rm -rf $(BUILD)

-include $(shell find $(BUILD) -name '*.d' 2>/dev/null)
