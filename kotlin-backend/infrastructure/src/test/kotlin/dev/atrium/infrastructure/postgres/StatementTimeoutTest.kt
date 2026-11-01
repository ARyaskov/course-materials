package dev.atrium.infrastructure.postgres

import io.kotest.assertions.throwables.shouldThrow
import io.kotest.matchers.shouldBe
import org.junit.jupiter.api.Test
import java.sql.SQLException

/** statement_timeout на соединении: pg_sleep(6) падает с 57014 (query_canceled), а не висит (урок 17.4). */
class StatementTimeoutTest : PostgresTest() {
    @Test
    fun `long statement is cancelled`() {
        dataSource.connection.use { c ->
            c.createStatement().execute("SET statement_timeout = '1s'")
            val e = shouldThrow<SQLException> { c.createStatement().execute("SELECT pg_sleep(6)") }
            e.sqlState shouldBe "57014"
        }
    }
}
