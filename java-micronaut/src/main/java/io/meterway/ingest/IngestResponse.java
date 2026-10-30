package io.meterway.ingest;

import io.micronaut.serde.annotation.Serdeable;

import java.util.List;

@Serdeable
public record IngestResponse(
        int accepted,
        int duplicated,
        int rejected,
        List<IngestOutcome> outcomes
) {

    public static IngestResponse of(List<IngestOutcome> outcomes) {
        int accepted = 0;
        int duplicated = 0;
        int rejected = 0;
        for (IngestOutcome outcome : outcomes) {
            switch (outcome) {
                case IngestOutcome.Accepted ignored -> accepted++;
                case IngestOutcome.Duplicate ignored -> duplicated++;
                case IngestOutcome.Conflict ignored -> rejected++;
                case IngestOutcome.Rejected ignored -> rejected++;
                case IngestOutcome.QuotaBlocked ignored -> rejected++;
            }
        }
        return new IngestResponse(accepted, duplicated, rejected, outcomes);
    }

    public boolean hasFailures() {
        return rejected > 0;
    }
}
