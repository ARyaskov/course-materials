package dev.atrium.application.ports

import dev.atrium.domain.BookingId
import dev.atrium.domain.MemberId
import kotlin.uuid.Uuid

data class Notification(
    val id: Uuid,
    val memberId: MemberId,
    val bookingId: BookingId,
    val template: String,
    val params: Map<String, String> = emptyMap(),
)

/** Внешний сервис Notify: письмо или сообщение участнику. */
interface NotificationSender {
    suspend fun send(notification: Notification)
}
