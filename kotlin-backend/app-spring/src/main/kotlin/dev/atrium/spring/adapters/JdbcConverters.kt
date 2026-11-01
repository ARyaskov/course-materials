package dev.atrium.spring.adapters

import dev.atrium.domain.TimeSlot
import org.postgresql.util.PGobject
import org.springframework.context.annotation.Configuration
import org.springframework.core.convert.converter.Converter
import org.springframework.data.convert.ReadingConverter
import org.springframework.data.convert.WritingConverter
import org.springframework.data.jdbc.repository.config.AbstractJdbcConfiguration
import java.time.OffsetDateTime
import java.time.ZoneOffset

@WritingConverter
object TimeSlotToPgObject : Converter<TimeSlot, PGobject> {
    override fun convert(source: TimeSlot): PGobject = PGobject().apply {
        type = "tstzrange"
        value = "[${source.start.atOffset(ZoneOffset.UTC)},${source.end.atOffset(ZoneOffset.UTC)})"
    }
}

@ReadingConverter
object PgObjectToTimeSlot : Converter<PGobject, TimeSlot> {
    private val pattern = Regex("""\["([^"]+)","([^"]+)"\)""")
    override fun convert(source: PGobject): TimeSlot {
        val (start, end) = requireNotNull(pattern.find(requireNotNull(source.value))) { "unexpected tstzrange: ${source.value}" }.destructured
        return TimeSlot(parse(start), parse(end))
    }

    private fun parse(raw: String) = OffsetDateTime.parse(raw.replace(' ', 'T').replace("+00", "Z")).toInstant()
}

@Configuration
class JdbcConvertersConfig : AbstractJdbcConfiguration() {
    override fun userConverters(): List<Any> = listOf(TimeSlotToPgObject, PgObjectToTimeSlot)
}
