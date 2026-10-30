package beacon.parser;

import java.util.List;

/** Результат разбора CSV-файла с проверками: что удалось разобрать и что нет. */
public record CheckImport(List<Row> rows, List<String> errors) {

    public record Row(String serviceKey, String name, String method, String url,
                      int expectedStatus, int timeoutMs, int intervalSeconds) {}

    public boolean isEmpty() {
        return rows.isEmpty();
    }
}
