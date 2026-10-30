package beacon.api;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/**
 * Тело POST /api/v1/orgs/:slug/checks.
 *
 * <p>Запись Java 27 плюс {@code @JsonIgnoreProperties(ignoreUnknown = true)}: клиент может
 * прислать поле, о котором эта версия сервера не знает, и запрос всё равно пройдёт.
 * Проверка значений — не задача Jackson, она в {@link #validate()}.
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public record CreateCheckRequest(
        String serviceKey,
        String name,
        String method,
        String url,
        Integer expectedStatus,
        String bodyContains,
        Integer timeoutMs,
        Integer intervalSeconds) {

    public java.util.List<String> validate() {
        var errors = new java.util.ArrayList<String>();
        if (isBlank(serviceKey)) {
            errors.add("serviceKey: обязательное поле");
        }
        if (isBlank(name)) {
            errors.add("name: обязательное поле");
        }
        if (isBlank(url) || !(url.startsWith("http://") || url.startsWith("https://"))) {
            errors.add("url: ожидается абсолютный http(s)-адрес");
        }
        if (method != null && !java.util.Set.of("GET", "HEAD", "POST").contains(method.toUpperCase())) {
            errors.add("method: допустимы GET, HEAD, POST");
        }
        if (expectedStatus != null && (expectedStatus < 100 || expectedStatus > 599)) {
            errors.add("expectedStatus: код вне диапазона 100..599");
        }
        if (timeoutMs != null && (timeoutMs < 100 || timeoutMs > 60_000)) {
            errors.add("timeoutMs: допустимо 100..60000");
        }
        if (intervalSeconds != null && (intervalSeconds < 10 || intervalSeconds > 86_400)) {
            errors.add("intervalSeconds: допустимо 10..86400");
        }
        return errors;
    }

    public String methodOrDefault() {
        return method == null || method.isBlank() ? "GET" : method.toUpperCase();
    }

    public int expectedStatusOrDefault() {
        return expectedStatus == null ? 200 : expectedStatus;
    }

    public int timeoutOrDefault() {
        return timeoutMs == null ? 10_000 : timeoutMs;
    }

    public int intervalOrDefault() {
        return intervalSeconds == null ? 60 : intervalSeconds;
    }

    private static boolean isBlank(String value) {
        return value == null || value.isBlank();
    }
}
