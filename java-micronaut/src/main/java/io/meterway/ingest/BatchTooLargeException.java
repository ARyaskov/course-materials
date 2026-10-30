package io.meterway.ingest;

import io.meterway.domain.MeterwayException;

public class BatchTooLargeException extends MeterwayException {

    private final int size;
    private final int maxSize;

    public BatchTooLargeException(int size, int maxSize) {
        super("Батч из %d событий превышает предел %d".formatted(size, maxSize));
        this.size = size;
        this.maxSize = maxSize;
    }

    public int size() {
        return size;
    }

    public int maxSize() {
        return maxSize;
    }

    @Override
    public String problemType() {
        return "batch-too-large";
    }
}
