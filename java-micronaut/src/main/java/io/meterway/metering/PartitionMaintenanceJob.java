package io.meterway.metering;

import io.micronaut.context.annotation.Requires;
import io.micronaut.scheduling.TaskExecutors;
import io.micronaut.scheduling.annotation.ExecuteOn;
import io.micronaut.scheduling.annotation.Scheduled;
import io.micronaut.transaction.TransactionOperations;
import jakarta.inject.Singleton;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.time.Clock;
import java.time.LocalDate;
import java.time.ZoneOffset;

/**
 * Создаёт секции таблицы событий заранее.
 * <p>
 * Здесь показан программный доступ к транзакции: {@link TransactionOperations} позволяет
 * выполнить произвольный SQL на том же соединении, что и репозитории, когда декларативного
 * {@code @Transactional} и Micronaut Data не хватает.
 */
@Singleton
@Requires(property = "meterway.partitions.auto-create", value = "true", defaultValue = "true")
public class PartitionMaintenanceJob {

    private static final Logger LOG = LoggerFactory.getLogger(PartitionMaintenanceJob.class);

    private final TransactionOperations<Connection> transactions;
    private final Clock clock;

    public PartitionMaintenanceJob(TransactionOperations<Connection> transactions, Clock clock) {
        this.transactions = transactions;
        this.clock = clock;
    }

    @Scheduled(cron = "${meterway.partitions.cron:0 0 3 * * *}")
    @ExecuteOn(TaskExecutors.BLOCKING)
    public void ensureUpcomingPartitions() {
        LocalDate today = LocalDate.ofInstant(clock.instant(), ZoneOffset.UTC);
        for (int monthsAhead = 0; monthsAhead <= 2; monthsAhead++) {
            LocalDate month = today.plusMonths(monthsAhead).withDayOfMonth(1);
            String created = transactions.executeWrite(status -> {
                try (PreparedStatement statement = status.getConnection()
                        .prepareStatement("select meterway_ensure_events_partition(?)")) {
                    statement.setObject(1, month);
                    try (ResultSet rs = statement.executeQuery()) {
                        return rs.next() ? rs.getString(1) : null;
                    }
                }
            });
            LOG.debug("Секция событий на {}: {}", month, created);
        }
    }
}
