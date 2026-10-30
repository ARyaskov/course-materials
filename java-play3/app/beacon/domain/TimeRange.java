package beacon.domain;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.Optional;
import play.mvc.QueryStringBindable;

/**
 * Интервал времени выборки, приходящий в query string как {@code ?range=24h} или
 * {@code ?range=7d}. Реализует {@link QueryStringBindable}, поэтому контроллер получает
 * уже разобранное значение, а не строку.
 */
public final class TimeRange implements QueryStringBindable<TimeRange> {

    private Duration window;

    public TimeRange() {
        this.window = Duration.ofHours(24);
    }

    public TimeRange(Duration window) {
        if (window.isNegative() || window.isZero() || window.toDays() > 366) {
            throw new IllegalArgumentException("интервал должен быть от 1 секунды до 366 дней");
        }
        this.window = window;
    }

    public static TimeRange lastDay() {
        return new TimeRange(Duration.ofHours(24));
    }

    public static TimeRange parse(String raw) {
        String text = raw.trim().toLowerCase();
        try {
            char unit = text.charAt(text.length() - 1);
            long amount = Long.parseLong(text.substring(0, text.length() - 1));
            Duration duration = switch (unit) {
                case 'm' -> Duration.ofMinutes(amount);
                case 'h' -> Duration.ofHours(amount);
                case 'd' -> Duration.ofDays(amount);
                default -> throw new IllegalArgumentException("неизвестная единица: " + unit);
            };
            return new TimeRange(duration);
        } catch (RuntimeException e) {
            throw new IllegalArgumentException("не разобран интервал '" + raw + "', ожидается 30m, 24h, 7d");
        }
    }

    public Duration window() {
        return window;
    }

    public Instant from(Instant now) {
        return now.minus(window);
    }

    @Override
    public Optional<TimeRange> bind(String key, Map<String, String[]> data) {
        String[] values = data.get(key);
        if (values == null || values.length == 0 || values[0].isBlank()) {
            return Optional.empty();
        }
        return Optional.of(parse(values[0]));
    }

    @Override
    public String unbind(String key) {
        return key + "=" + window.toHours() + "h";
    }

    @Override
    public String javascriptUnbind() {
        return "function(k, v) { return k + '=' + encodeURIComponent(v); }";
    }

    @Override
    public String toString() {
        return window.toHours() + "h";
    }
}
