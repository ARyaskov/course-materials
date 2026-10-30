package beacon.domain;

import java.util.Objects;
import java.util.regex.Pattern;
import play.mvc.PathBindable;

/**
 * Стабильный человекочитаемый идентификатор сервиса внутри организации: {@code api}, {@code web}.
 *
 * <p>Класс реализует {@link PathBindable}, поэтому в conf/routes можно писать
 * {@code key: ServiceKey} вместо {@code key: String} — проверка формата выполняется
 * до входа в контроллер, а неверное значение превращается в 400.
 *
 * <p>Требование Play: у биндера должен быть публичный конструктор без аргументов —
 * роутер создаёт «пустой» экземпляр и вызывает на нём {@link #bind(String, String)}.
 */
public final class ServiceKey implements PathBindable<ServiceKey> {

    private static final Pattern VALID = Pattern.compile("[a-z0-9][a-z0-9-]{0,62}");

    private String value;

    public ServiceKey() {
        // требуется роутером Play
    }

    public ServiceKey(String value) {
        this.value = validated(value);
    }

    public static ServiceKey of(String value) {
        return new ServiceKey(value);
    }

    private static String validated(String value) {
        if (value == null || !VALID.matcher(value).matches()) {
            throw new IllegalArgumentException(
                    "ключ сервиса должен соответствовать [a-z0-9][a-z0-9-]{0,62}, получено: " + value);
        }
        return value;
    }

    public String value() {
        return value;
    }

    @Override
    public ServiceKey bind(String key, String txt) {
        return new ServiceKey(txt);
    }

    @Override
    public String unbind(String key) {
        return value;
    }

    @Override
    public String javascriptUnbind() {
        return "function(k, v) { return encodeURIComponent(v); }";
    }

    @Override
    public boolean equals(Object other) {
        return other instanceof ServiceKey sk && Objects.equals(value, sk.value);
    }

    @Override
    public int hashCode() {
        return Objects.hashCode(value);
    }

    @Override
    public String toString() {
        return value;
    }
}
