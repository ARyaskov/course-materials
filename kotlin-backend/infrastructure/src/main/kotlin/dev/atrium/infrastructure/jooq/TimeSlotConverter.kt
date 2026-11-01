package dev.atrium.infrastructure.jooq

import dev.atrium.domain.TimeSlot
import org.jooq.Converter
import org.postgresql.util.PGobject
import java.time.OffsetDateTime
import java.time.ZoneOffset

/** forcedTypes для bookings.slot: сгенерированный BookingsRecord.slot сразу типа TimeSlot. */
class TimeSlotConverter : Converter<Any, TimeSlot> {
    override fun from(databaseObject: Any?): TimeSlot? {
        val raw = (databaseObject as? PGobject)?.value ?: databaseObject?.toString() ?: return null
        val (start, end) = raw.removeSurrounding("[", ")").split(',').map { it.trim('"') }
        return TimeSlot(parse(start), parse(end))
    }

    override fun to(userObject: TimeSlot?): Any? = userObject?.let {
        PGobject().apply { type = "tstzrange"; value = "[${it.start.atOffset(ZoneOffset.UTC)},${it.end.atOffset(ZoneOffset.UTC)})" }
    }

    override fun fromType(): Class<Any> = Any::class.java
    override fun toType(): Class<TimeSlot> = TimeSlot::class.java

    private fun parse(raw: String) = OffsetDateTime.parse(raw.replace(' ', 'T').replace("+00", "Z")).toInstant()
}
