package dev.atrium.infrastructure.jooq

import dev.atrium.domain.RoomId
import dev.atrium.infrastructure.jooq.generated.tables.references.BOOKINGS
import dev.atrium.infrastructure.jooq.generated.tables.references.ROOMS
import org.jooq.DSLContext
import org.jooq.DatePart
import org.jooq.impl.DSL.extract
import org.jooq.impl.DSL.field
import org.jooq.impl.DSL.name
import org.jooq.impl.DSL.partitionBy
import org.jooq.impl.DSL.rowNumber
import org.jooq.impl.DSL.select
import org.jooq.impl.DSL.sum
import org.jooq.impl.DSL.with
import java.time.OffsetDateTime
import java.util.UUID
import kotlin.uuid.toKotlinUuid

data class RoomUtilizationRow(val roomId: RoomId, val roomName: String, val minutesBooked: Long)

private val lowerSlot = field("lower({0})", OffsetDateTime::class.java, BOOKINGS.SLOT)
private val upperSlot = field("upper({0})", OffsetDateTime::class.java, BOOKINGS.SLOT)

/** Топ-N комнат по занятым минутам в каждой локации: CTE + оконная функция, типобезопасно. */
fun DSLContext.topRoomsByUtilization(from: OffsetDateTime, to: OffsetDateTime, perLocation: Int): List<RoomUtilizationRow> {
    val minutes = sum(extract(upperSlot, DatePart.EPOCH).minus(extract(lowerSlot, DatePart.EPOCH)).div(60))
    val booked = name("booked").`as`(
        select(BOOKINGS.ROOM_ID.`as`("room_id"), minutes.`as`("minutes"))
            .from(BOOKINGS)
            .where(BOOKINGS.STATUS.`in`("CONFIRMED", "NO_SHOW"))
            .and(BOOKINGS.CREATED_AT.between(from, to))
            .groupBy(BOOKINGS.ROOM_ID),
    )
    val bookedMinutes = field(name("booked", "minutes"), Long::class.java)
    val bookedRoom = field(name("booked", "room_id"), UUID::class.java)
    val rank = rowNumber().over(partitionBy(ROOMS.LOCATION_ID).orderBy(bookedMinutes.desc()))
    return with(booked)
        .select(ROOMS.ID, ROOMS.LOCATION_ID, ROOMS.NAME, bookedMinutes, rank.`as`("rank"))
        .from(ROOMS)
        .join(booked).on(ROOMS.ID.eq(bookedRoom))
        .qualify(rank.le(perLocation))
        .fetch { RoomUtilizationRow(RoomId(requireNotNull(it[ROOMS.ID]).toKotlinUuid()), requireNotNull(it[ROOMS.NAME]), requireNotNull(it[bookedMinutes])) }
}
