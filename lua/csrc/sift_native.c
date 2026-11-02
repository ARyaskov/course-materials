/* Необязательное C-ускорение горячего участка.
 *
 * Профиль показывает, что львиная доля времени уходит на разбор JSON —
 * и внутри него на посимвольный проход по строке. Здесь вынесены две
 * операции, которые в Lua стоят дороже всего:
 *
 *   sift_native.scan_string(s, init)  — найти конец JSON-строки, сообщив,
 *                                       есть ли внутри экранирования;
 *   sift_native.count_lines(s)        — посчитать переводы строки в буфере.
 *
 * Модуль не обязателен: sift.json грузит его через pcall и при отсутствии
 * работает на чистом Lua. Это осознанный контракт — инструмент должен
 * запускаться там, где компилятора нет.
 *
 * Сборка: make -C csrc          (см. csrc/Makefile)
 */

#include <string.h>

#include "lua.h"
#include "lauxlib.h"

/* scan_string(s, init) -> stop, has_escapes
 *
 * s[init] — первый байт ПОСЛЕ открывающей кавычки. Возвращает позицию
 * закрывающей кавычки (1-based) и признак того, встречались ли обратные
 * слэши. Если строка не закрыта, возвращает fail (nil).
 */
static int l_scan_string (lua_State *L) {
  size_t len;
  const char *s = luaL_checklstring(L, 1, &len);
  lua_Integer init = luaL_optinteger(L, 2, 1);
  int escaped = 0;
  size_t i;

  if (init < 1) init = 1;
  for (i = (size_t)init - 1; i < len; i++) {
    char c = s[i];
    if (c == '\\') {
      escaped = 1;
      i++;                 /* следующий байт экранирован, пропускаем */
    }
    else if (c == '"') {
      lua_pushinteger(L, (lua_Integer)i + 1);
      lua_pushboolean(L, escaped);
      return 2;
    }
  }
  luaL_pushfail(L);
  lua_pushliteral(L, "unterminated string");
  return 2;
}

/* count_lines(s) -> n — сколько '\n' в буфере. */
static int l_count_lines (lua_State *L) {
  size_t len;
  const char *s = luaL_checklstring(L, 1, &len);
  const char *p = s;
  const char *end = s + len;
  lua_Integer n = 0;

  while (p < end) {
    const char *nl = (const char *)memchr(p, '\n', (size_t)(end - p));
    if (nl == NULL) break;
    n++;
    p = nl + 1;
  }
  lua_pushinteger(L, n);
  return 1;
}

static const luaL_Reg sift_native[] = {
  {"scan_string", l_scan_string},
  {"count_lines", l_count_lines},
  {NULL, NULL}
};

/* Имя обязано совпадать с именем модуля: require "sift_native" ищет
 * в разделяемой библиотеке символ luaopen_sift_native. */
int luaopen_sift_native (lua_State *L) {
  luaL_newlib(L, sift_native);
  lua_pushliteral(L, "0.3.0");
  lua_setfield(L, -2, "_VERSION");
  return 1;
}
