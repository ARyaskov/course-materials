package dev.atrium.infrastructure.postgres

import io.kotest.matchers.string.shouldContain
import io.kotest.matchers.string.shouldNotContain
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import java.time.OffsetDateTime
import java.util.UUID

/** Планы горячих запросов используют ожидаемые индексы; на пустой таблице планировщик выберет Seq Scan — нужен seed (урок 17.4). */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class QueryPlansTest : PostgresTest() {
    private val room = UUID.fromString("00000000-0000-0000-0000-000000000101")

    @BeforeAll
    fun seedLoad() {
        val sql = java.io.File("../scripts/seed-load.sql").readText() // рабочая директория теста — модуль
        dataSource.connection.use { c -> c.createStatement().execute(sql); c.createStatement().execute("ANALYZE bookings") }
    }

    @Test
    fun `active bookings by room use the gist index`() {
        val from = OffsetDateTime.now().plusDays(1)
        val plan = explain("SELECT * FROM bookings WHERE room_id = ? AND slot && tstzrange(?, ?, '[)') AND status IN ('PENDING','CONFIRMED')", room, from, from.plusHours(1))
        plan shouldContain "bookings_room_slot_active_idx"
        plan shouldNotContain "Seq Scan on bookings"
    }

    @Test
    fun `member list by cursor is an index scan`() {
        val plan = explain("SELECT * FROM bookings WHERE member_id = ? AND (created_at, id) < (?, ?) ORDER BY created_at DESC, id DESC LIMIT 21", UUID.randomUUID(), OffsetDateTime.now(), UUID.randomUUID())
        plan shouldContain "Index Scan"
        plan shouldNotContain "Seq Scan on bookings"
    }

    @Test
    fun `expired pending selection uses the partial index`() {
        val plan = explain("SELECT * FROM bookings WHERE status = 'PENDING' AND expires_at < ? ORDER BY expires_at LIMIT 100 FOR UPDATE SKIP LOCKED", OffsetDateTime.now())
        plan shouldContain "bookings_pending_expires_idx"
    }

    private fun explain(sql: String, vararg params: Any): String = dataSource.connection.use { c ->
        c.prepareStatement("EXPLAIN (FORMAT TEXT) $sql").apply { params.forEachIndexed { i, p -> setObject(i + 1, p) } }
            .executeQuery().use { rs -> generateSequence { if (rs.next()) rs.getString(1) else null }.joinToString("\n") }
    }
}
