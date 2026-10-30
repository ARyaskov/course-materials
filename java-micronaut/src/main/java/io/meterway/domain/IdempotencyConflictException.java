package io.meterway.domain;

public class IdempotencyConflictException extends MeterwayException {

    private final String idempotencyKey;

    public IdempotencyConflictException(String idempotencyKey) {
        super("Ключ идемпотентности уже использован с другим телом запроса: " + idempotencyKey);
        this.idempotencyKey = idempotencyKey;
    }

    public String idempotencyKey() {
        return idempotencyKey;
    }

    @Override
    public String problemType() {
        return "idempotency-conflict";
    }
}
