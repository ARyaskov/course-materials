package dev.atrium.infrastructure.postgres

import io.kotest.assertions.throwables.shouldThrow
import io.kotest.matchers.collections.shouldContainExactly
import io.kotest.matchers.shouldBe
import org.flywaydb.core.Flyway
import org.junit.jupiter.api.Test
import java.sql.SQLException

class MigrationsTest : PostgresTest() {
    @Test
    fun `all migrations are applied and validate passes`() {
        val flyway = Flyway.configure().dataSource(dataSource).locations("classpath:db/migration", "classpath:db/testdata").load()
        flyway.validate()
        flyway.info().applied().map { it.version.version } shouldContainExactly listOf("001", "002", "003", "004", "005", "006", "900")
    }

    @Test
    fun `booking constraints are enforced by the schema`() {
        dataSource.connection.use { c ->
            val e = shouldThrow<SQLException> {
                c.createStatement().execute(
                    "INSERT INTO bookings (id, room_id, member_id, slot, status, created_at) VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000101', gen_random_uuid(), tstzrange(now(), now() + interval '1 hour', '[)'), 'CONFIRMED', now())",
                )
            }
            e.sqlState shouldBe "23514" // bookings_confirmed_has_payment
        }
    }
}
