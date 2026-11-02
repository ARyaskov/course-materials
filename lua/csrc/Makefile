# Сборка необязательного C-модуля sift_native.
#
# LUA_INCDIR должен указывать на каталог с lua.h. Если Lua поставлен через
# пакетный менеджер, путь обычно /usr/include/lua5.5; при сборке из исходников
# укажите свой: make LUA_INCDIR=$HOME/.local/include

LUA_INCDIR ?= /usr/include/lua5.5
CC         ?= cc
CFLAGS     ?= -O2 -fPIC -Wall -Wextra -std=c99
LDFLAGS    ?= -shared
TARGET      = ../sift_native.so

ifeq ($(shell uname -s),Darwin)
LDFLAGS = -bundle -undefined dynamic_lookup
endif

$(TARGET): sift_native.c
	$(CC) $(CFLAGS) -I$(LUA_INCDIR) $(LDFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)

.PHONY: clean
