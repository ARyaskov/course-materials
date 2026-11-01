package dev.atrium.infrastructure.exposed

import org.jetbrains.exposed.v1.core.Table
import org.jetbrains.exposed.v1.core.java.javaUUID
import org.jetbrains.exposed.v1.javatime.timestampWithTimeZone

/** Описание таблиц для DSL. Схему создают миграции Flyway; SchemaUtils.create не используется. */
object Rooms : Table("rooms") {
    val id = javaUUID("id")
    val locationId = javaUUID("location_id")
    val name = text("name")
    val capacity = integer("capacity")
    val pricePerHour = decimal("price_per_hour", 12, 2)
    val currency = char("currency", 3)
    override val primaryKey = PrimaryKey(id)
}

object Bookings : Table("bookings") {
    val id = javaUUID("id")
    val roomId = javaUUID("room_id").references(Rooms.id)
    val memberId = javaUUID("member_id")
    val slot = tstzrange("slot")
    val status = text("status")
    val expiresAt = timestampWithTimeZone("expires_at").nullable()
    val paymentId = text("payment_id").nullable()
    val cancelReason = text("cancel_reason").nullable()
    val cancelledAt = timestampWithTimeZone("cancelled_at").nullable()
    val version = long("version")
    val createdAt = timestampWithTimeZone("created_at")
    override val primaryKey = PrimaryKey(id)
}
