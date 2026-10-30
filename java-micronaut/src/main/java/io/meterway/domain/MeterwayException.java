package io.meterway.domain;

/** Базовое доменное исключение. Всё, что наследуется от него, превращается в problem+json. */
public abstract class MeterwayException extends RuntimeException {

    protected MeterwayException(String message) {
        super(message);
    }

    protected MeterwayException(String message, Throwable cause) {
        super(message, cause);
    }

    /** Идентификатор типа проблемы, попадающий в поле {@code type} ответа RFC 9457. */
    public abstract String problemType();
}
