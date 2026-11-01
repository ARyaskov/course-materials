package dev.atrium.infrastructure.exposed

import dev.atrium.domain.TimeSlot
import org.jetbrains.exposed.v1.core.Column
import org.jetbrains.exposed.v1.core.ColumnType
import org.jetbrains.exposed.v1.core.Expression
import org.jetbrains.exposed.v1.core.Op
import org.jetbrains.exposed.v1.core.QueryBuilder
import org.jetbrains.exposed.v1.core.Table
import org.postgresql.util.PGobject
import java.time.OffsetDateTime
import java.time.ZoneOffset

/** Кастомный тип колонки: tstzrange ↔ доменный TimeSlot. Разбор строки — хрупкое место range-типов. */
class TstzRangeColumnType : ColumnType<TimeSlot>() {
    override fun sqlType(): String = "tstzrange"

    override fun valueFromDB(value: Any): TimeSlot {
        val raw = (value as? PGobject)?.value ?: value.toString()
        val (start, end) = raw.removeSurrounding("[", ")").split(',').map { it.trim('"') }
        return TimeSlot(parsePg(start), parsePg(end))
    }

    override fun notNullValueToDB(value: TimeSlot): Any = PGobject().apply {
        type = "tstzrange"
        this.value = "[${value.start.atOffset(ZoneOffset.UTC)},${value.end.atOffset(ZoneOffset.UTC)})"
    }

    private fun parsePg(raw: String) = OffsetDateTime.parse(raw.replace(' ', 'T').replace("+00", "Z")).toInstant()
}

fun Table.tstzrange(name: String): Column<TimeSlot> = registerColumn(name, TstzRangeColumnType())

/** Оператор && для range: slot overlaps TimeSlot(...) в where { }. */
class OverlapsOp(private val column: Column<TimeSlot>, private val slot: TimeSlot) : Op<Boolean>() {
    override fun toQueryBuilder(queryBuilder: QueryBuilder) = queryBuilder {
        +column
        +" && "
        registerArgument(column.columnType, slot)
    }
}

infix fun Column<TimeSlot>.overlaps(slot: TimeSlot): Op<Boolean> = OverlapsOp(this, slot)
