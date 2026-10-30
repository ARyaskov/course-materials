package beacon.domain;

import java.time.LocalDate;

/** Дневной агрегат по проверке — то, из чего рисуется полоса аптайма за 90 дней. */
public record UptimeDay(long checkId, LocalDate day, int upCount, int totalCount, long avgDurationMs) {

    public double ratio() {
        return totalCount == 0 ? 1.0 : (double) upCount / totalCount;
    }
}
