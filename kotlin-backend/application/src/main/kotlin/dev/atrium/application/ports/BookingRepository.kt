package dev.atrium.application.ports

import dev.atrium.domain.Booking
import dev.atrium.domain.BookingId
import dev.atrium.domain.MemberId
import dev.atrium.domain.RoomId
import dev.atrium.domain.TimeSlot
import java.time.Instant
import kotlinx.coroutines.flow.Flow

interface BookingRepository {
    suspend fun find(id: BookingId): Booking?

    /** Сохраняет новую или обновлённую бронь; при конфликте версии бросает OptimisticLockException. */
    suspend fun save(booking: Booking): Booking

    suspend fun findActiveByRoom(roomId: RoomId, from: Instant, to: Instant): List<Booking>

    suspend fun findByMember(memberId: MemberId, cursor: BookingCursor?, limit: Int): List<Booking>

    suspend fun findPendingExpiredBefore(now: Instant, limit: Int): List<Booking>

    /** Один запрос по списку комнат вместо N+1; результат сгруппирован по комнате. */
    suspend fun findActiveByRooms(roomIds: Collection<RoomId>, from: Instant, to: Instant): Map<RoomId, List<Booking>>

    /** Ленивый поток броней по курсору (createdAt, id): соединение открывается на каждый батч. */
    fun streamCreatedBetween(from: Instant, to: Instant, batchSize: Int, after: BookingCursor? = null): Flow<Booking>
}

/** Exclusion constraint отверг вставку: гонка двух броней на один слот. Use case превращает в SlotTaken. */
class SlotConflictException(val roomId: RoomId, val slot: TimeSlot, cause: Throwable? = null) :
    RuntimeException("Slot conflict for room $roomId at $slot", cause)

/** Курсор keyset-пагинации: последняя увиденная пара (createdAt, id). */
data class BookingCursor(val createdAt: Instant, val id: BookingId)

/** Версия строки изменилась между чтением и записью: другой запрос успел обновить бронь. */
class OptimisticLockException(id: BookingId) : RuntimeException("Booking $id was modified concurrently")
