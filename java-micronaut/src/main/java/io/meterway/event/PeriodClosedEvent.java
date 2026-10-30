package io.meterway.event;

import io.meterway.billing.ClosingReport;

/**
 * Расчётный период закрыт: счета выставлены, агрегаты зафиксированы.
 * <p>
 * Событие доменное, а не техническое: оно описывает факт предметной области, а не вызов
 * метода. Издатель не знает, кто его слушает, и работает одинаково при любом их числе.
 */
public record PeriodClosedEvent(ClosingReport report) {
}
