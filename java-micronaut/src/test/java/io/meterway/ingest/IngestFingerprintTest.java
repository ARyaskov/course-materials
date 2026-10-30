package io.meterway.ingest;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;

class IngestFingerprintTest {

    private static UsageEventRequest request(BigDecimal quantity, Map<String, Object> properties) {
        return new UsageEventRequest(
                "key-1", "api.requests", "cust-north",
                Instant.parse("2026-05-01T10:00:00Z"), quantity, properties);
    }

    @Test
    @DisplayName("Одинаковые события дают одинаковый отпечаток независимо от порядка свойств")
    void stableAcrossPropertyOrder() {
        Map<String, Object> first = new LinkedHashMap<>();
        first.put("region", "eu");
        first.put("endpoint", "/v1/items");

        Map<String, Object> second = new LinkedHashMap<>();
        second.put("endpoint", "/v1/items");
        second.put("region", "eu");

        assertEquals(
                UsageIngestService.fingerprint(request(BigDecimal.ONE, first)),
                UsageIngestService.fingerprint(request(BigDecimal.ONE, second)));
    }

    @Test
    @DisplayName("Незначащие нули в количестве не меняют отпечаток")
    void ignoresTrailingZeros() {
        assertEquals(
                UsageIngestService.fingerprint(request(new BigDecimal("1.50"), Map.of())),
                UsageIngestService.fingerprint(request(new BigDecimal("1.5"), Map.of())));
    }

    @Test
    @DisplayName("Изменение количества меняет отпечаток: это уже другое событие")
    void detectsChangedQuantity() {
        assertNotEquals(
                UsageIngestService.fingerprint(request(BigDecimal.ONE, Map.of())),
                UsageIngestService.fingerprint(request(BigDecimal.TEN, Map.of())));
    }
}
