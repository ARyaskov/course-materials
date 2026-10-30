package io.meterway.ingest;

import com.fasterxml.jackson.annotation.JsonSubTypes;
import com.fasterxml.jackson.annotation.JsonTypeInfo;
import io.micronaut.core.annotation.Nullable;
import io.micronaut.serde.annotation.Serdeable;

import java.util.UUID;

/**
 * Результат обработки одного события. Частичный успех батча — нормальный исход, а не ошибка.
 * <p>
 * Sealed-иерархия делает {@code switch} в контроллере исчерпывающим: добавление нового исхода
 * ломает компиляцию везде, где его забыли обработать.
 * <p>
 * Для передачи по сети иерархии нужен дискриминатор: без поля {@code outcome} принимающая
 * сторона не может выбрать конкретный тип. Micronaut Serialization читает те же
 * {@code @JsonTypeInfo} и {@code @JsonSubTypes}, что и Jackson, но разбирает их при компиляции.
 */
@Serdeable
@JsonTypeInfo(use = JsonTypeInfo.Id.NAME, include = JsonTypeInfo.As.PROPERTY, property = "outcome")
@JsonSubTypes({
        @JsonSubTypes.Type(value = IngestOutcome.Accepted.class, name = "accepted"),
        @JsonSubTypes.Type(value = IngestOutcome.Duplicate.class, name = "duplicate"),
        @JsonSubTypes.Type(value = IngestOutcome.Conflict.class, name = "conflict"),
        @JsonSubTypes.Type(value = IngestOutcome.Rejected.class, name = "rejected"),
        @JsonSubTypes.Type(value = IngestOutcome.QuotaBlocked.class, name = "quota-blocked")
})
public sealed interface IngestOutcome {

    String idempotencyKey();

    /** Событие принято и сохранено. */
    @Serdeable
    record Accepted(String idempotencyKey, UUID eventId) implements IngestOutcome {
    }

    /** Событие уже было принято ранее с тем же телом: повтор безопасно проигнорирован. */
    @Serdeable
    record Duplicate(String idempotencyKey, UUID eventId) implements IngestOutcome {
    }

    /** Ключ занят событием с другим телом: источник переиспользовал ключ. */
    @Serdeable
    record Conflict(String idempotencyKey, String reason) implements IngestOutcome {
    }

    /** Событие отклонено: неизвестная метрика, неизвестный клиент, слишком старая дата. */
    @Serdeable
    record Rejected(String idempotencyKey, String code, String reason) implements IngestOutcome {
    }

    /** Квота исчерпана. */
    @Serdeable
    record QuotaBlocked(String idempotencyKey, String meterCode, long limit, long used,
                        @Nullable Long retryAfterSeconds) implements IngestOutcome {
    }
}
