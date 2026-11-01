package dev.atrium.application.testing

import dev.atrium.application.ports.BookingCursor
import dev.atrium.application.ports.OptimisticLockException
import dev.atrium.application.ports.BookingEvent
import dev.atrium.application.ports.BookingRepository
import dev.atrium.application.ports.Clock
import dev.atrium.application.ports.EventPublisher
import dev.atrium.application.ports.IdGenerator
import dev.atrium.application.ports.PaymentGateway
import dev.atrium.application.ports.PaymentResult
import dev.atrium.application.ports.RoomRepository
import dev.atrium.domain.Booking
import dev.atrium.domain.BookingId
import dev.atrium.domain.BookingStatus
import dev.atrium.domain.Location
import dev.atrium.domain.LocationId
import dev.atrium.domain.MemberId
import dev.atrium.domain.Money
import dev.atrium.domain.PaymentId
import dev.atrium.domain.Room
import dev.atrium.domain.RoomId
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import java.time.Duration
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import kotlin.uuid.Uuid

class FixedClock(private var now: Instant) : Clock {
    override fun now(): Instant = now
    fun advance(by: Duration) { now += by }
}

class SequentialIds : IdGenerator {
    private var counter = 0L
    override fun nextBookingId(): BookingId = BookingId(Uuid.parse("00000000-0000-7000-8000-%012d".format(++counter)))
}

class RecordingEventPublisher : EventPublisher {
    val published = mutableListOf<BookingEvent>()
    override suspend fun publish(event: BookingEvent) { published += event }
}

/** Репозиторий в памяти с проверкой version — optimistic locking тестируется без базы. */
class InMemoryBookingRepository : BookingRepository {
    private val store = ConcurrentHashMap<BookingId, Booking>()
    var loadBatchCalls: Int = 0
        private set

    override suspend fun find(id: BookingId): Booking? = store[id]

    override suspend fun save(booking: Booking): Booking {
        val current = store[booking.id]
        if (current != null && current.version != booking.version) throw OptimisticLockException(booking.id)
        return booking.copy(version = booking.version + 1).also { store[it.id] = it }
    }

    override suspend fun findActiveByRoom(roomId: RoomId, from: Instant, to: Instant): List<Booking> =
        store.values.filter { it.roomId == roomId && it.isActive && it.slot.start < to && from < it.slot.end }

    override suspend fun findActiveByRooms(roomIds: Collection<RoomId>, from: Instant, to: Instant): Map<RoomId, List<Booking>> =
        roomIds.associateWith { findActiveByRoom(it, from, to) }.filterValues { it.isNotEmpty() }

    override suspend fun findByMember(memberId: MemberId, cursor: BookingCursor?, limit: Int): List<Booking> =
        store.values.asSequence()
            .filter { it.memberId == memberId }
            .sortedWith(compareByDescending<Booking> { it.createdAt }.thenByDescending { it.id.value.toString() })
            .filter { cursor == null || it.createdAt < cursor.createdAt || (it.createdAt == cursor.createdAt && it.id.value.toString() < cursor.id.value.toString()) }
            .take(limit)
            .toList()

    override suspend fun findPendingExpiredBefore(now: Instant, limit: Int): List<Booking> =
        store.values.filter { (it.status as? BookingStatus.Pending)?.expiresAt?.let { e -> e < now } == true }.take(limit)

    override fun streamCreatedBetween(from: Instant, to: Instant, batchSize: Int, after: BookingCursor?): Flow<Booking> = flow {
        val all = store.values.filter { it.createdAt >= from && it.createdAt < to }
            .filter { after == null || it.createdAt > after.createdAt || (it.createdAt == after.createdAt && it.id.value.toString() > after.id.value.toString()) }
            .sortedWith(compareBy<Booking> { it.createdAt }.thenBy { it.id.value.toString() })
        var offset = 0
        while (true) {
            loadBatchCalls++
            val batch = all.drop(offset).take(batchSize)
            if (batch.isEmpty()) break
            batch.forEach { emit(it) }
            offset += batch.size
        }
    }

    fun seed(vararg bookings: Booking) = bookings.forEach { store[it.id] = it }
}

class InMemoryRoomRepository(vararg seeds: Pair<Location, List<Room>>) : RoomRepository {
    private val locations = seeds.associate { it.first.id to it.first }
    private val rooms = seeds.flatMap { it.second }.associateBy { it.id }

    override suspend fun find(id: RoomId): Room? = rooms[id]
    override suspend fun findByLocation(locationId: LocationId): List<Room> = rooms.values.filter { it.locationId == locationId }
    override suspend fun findLocation(id: LocationId): Location? = locations[id]
}

/** Платёжный шлюз с программируемым исходом: по умолчанию всё списывается. */
class FakePaymentGateway(var nextCharge: (Money) -> PaymentResult = { PaymentResult.Charged(PaymentId("pay_${Uuid.random()}")) }) : PaymentGateway {
    val charges = mutableListOf<Pair<BookingId, String>>()
    val refunds = mutableListOf<PaymentId>()
    var lastAmount: Money? = null
        private set

    override suspend fun charge(bookingId: BookingId, amount: Money, idempotencyKey: String): PaymentResult {
        charges += bookingId to idempotencyKey
        lastAmount = amount
        return nextCharge(amount)
    }

    override suspend fun refund(paymentId: PaymentId): PaymentResult {
        refunds += paymentId
        return PaymentResult.Refunded(paymentId)
    }
}
