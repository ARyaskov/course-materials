package dev.atrium.infrastructure.postgres

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import dev.atrium.infrastructure.concurrency.databaseDispatcher
import org.flywaydb.core.Flyway
import org.junit.jupiter.api.AfterEach
import org.testcontainers.postgresql.PostgreSQLContainer
import javax.sql.DataSource

/** Один контейнер на JVM, миграции с тестовым seed один раз, TRUNCATE изменяемых таблиц после каждого теста. */
abstract class PostgresTest {
    companion object {
        @JvmStatic
        protected val postgres: PostgreSQLContainer = PostgreSQLContainer("postgres:18")
            .withReuse(true)
            .withCommand("postgres", "-c", "shared_preload_libraries=pg_stat_statements", "-c", "log_min_duration_statement=0")
            .also { it.start() }

        @JvmStatic
        protected val dataSource: DataSource by lazy {
            HikariDataSource(
                HikariConfig().apply {
                    jdbcUrl = postgres.jdbcUrl
                    username = postgres.username
                    password = postgres.password
                    maximumPoolSize = 4
                },
            ).also { Flyway.configure().dataSource(it).locations("classpath:db/migration", "classpath:db/testdata").load().migrate() }
        }

        @JvmStatic protected val dbDispatcher = databaseDispatcher(poolSize = 4)
        @JvmStatic protected val transactions by lazy { JdbcTransactionRunner(dataSource, dbDispatcher) }
    }

    @AfterEach
    fun cleanup() {
        dataSource.connection.use {
            it.createStatement().execute("TRUNCATE bookings, outbox, processed_events, notification_outbox, idempotency_keys, backfill_runs, room_utilization CASCADE")
        }
    }
}
