package dev.atrium.infrastructure.postgres

import dev.atrium.application.ports.OptimisticLockException
import dev.atrium.application.ports.SlotConflictException
import dev.atrium.application.runCatchingCancellable
import dev.atrium.application.transactional
import dev.atrium.domain.BookingStatus
import dev.atrium.domain.PaymentId
import dev.atrium.domain.RoomId
import dev.atrium.domain.TimeSlot
import dev.atrium.domain.aBooking
import io.kotest.assertions.throwables.shouldThrow
import io.kotest.matchers.collections.shouldHaveSize
import io.kotest.matchers.shouldBe
import io.kotest.matchers.types.shouldBeInstanceOf
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Test
import java.time.Duration
import java.time.Instant
import kotlin.uuid.Uuid

class BookingConcurrencyTest : PostgresTest() {
    private val repository = JdbcBookingRepository(dataSource, dbDispatcher)
    private val room = RoomId(Uuid.parse("00000000-0000-0000-0000-000000000101")) // из V900

    @Test
    fun `exclusion constraint rejects the second overlapping booking`() = runBlocking {
        val slot = TimeSlot.of(Instant.parse("2027-01-10T10:00:00Z"), Duration.ofHours(1))
        val results = (1..2).map {
            async(Dispatchers.Default) {
                runCatchingCancellable { transactions.transactional { repository.save(aBooking { roomId = room; start = slot.start; duration = slot.duration }) } }
            }
        }.awaitAll()

        results.count { it.isSuccess } shouldBe 1
        results.single { it.isFailure }.exceptionOrNull().shouldBeInstanceOf<SlotConflictException>()
        repository.findActiveByRoom(room, slot.start, slot.end) shouldHaveSize 1
    }

    @Test
    fun `optimistic lock stops the second writer`() = runBlocking {
        val saved = repository.save(aBooking { roomId = room })
        val first = saved.confirm(PaymentId("p1"))
        val second = saved.confirm(PaymentId("p2"))
        repository.save(first)
        shouldThrow<OptimisticLockException> { repository.save(second) }
    }

    @Test
    fun `skip locked splits expired bookings between workers`() = runBlocking {
        repeat(100) { i ->
            repository.save(aBooking { roomId = room; slot(Instant.parse("2027-01-10T10:00:00Z") + Duration.ofHours(i.toLong())); status = BookingStatus.Pending(expiresAt = Instant.EPOCH) })
        }
        val taken = (1..20).map {
            async(Dispatchers.Default) {
                transactions.transactional { repository.findPendingExpiredBefore(Instant.now(), 5).also { batch -> batch.forEach { repository.save(it.expire()) } } }
            }
        }.awaitAll().flatten()
        taken shouldHaveSize 100
        taken.map { it.id }.toSet() shouldHaveSize 100
    }
}
