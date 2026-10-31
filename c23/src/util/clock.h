#ifndef NESTOR_UTIL_CLOCK_H
#define NESTOR_UTIL_CLOCK_H

#include <stdint.h>

/* Монотонное время в наносекундах — для измерений длительности. */
uint64_t nst_now_mono_ns(void);
/* Настенное время в миллисекундах — для меток записей и логов. */
uint64_t nst_now_wall_ms(void);
/* Форматирование настенного времени в "YYYY-MM-DDThh:mm:ss.mmmZ". */
void nst_format_time_ms(uint64_t ms, char buf[static 32]);

#endif /* NESTOR_UTIL_CLOCK_H */
