package io.meterway.ingest;

import io.micronaut.serde.annotation.Serdeable;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;

import java.util.List;

@Serdeable
public record UsageEventBatchRequest(

        @NotEmpty
        @Size(max = 10_000, message = "Батч больше 10000 событий не принимается")
        @Valid
        List<UsageEventRequest> events
) {
}
