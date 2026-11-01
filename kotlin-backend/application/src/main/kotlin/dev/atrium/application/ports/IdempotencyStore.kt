package dev.atrium.application.ports

import dev.atrium.domain.BookingId
import dev.atrium.domain.MemberId

data class IdempotencyKey(val key: String, val requestHash: String)

sealed interface IdempotencyOutcome {
    data object Acquired : IdempotencyOutcome // новый ключ: выполнять
    data class Replay(val bookingId: BookingId, val status: Int) : IdempotencyOutcome // завершён: ответ по актуальной брони
    data object InProgress : IdempotencyOutcome // выполняется параллельно
    data object Mismatch : IdempotencyOutcome // тот же ключ, другое тело
}

interface IdempotencyStore {
    suspend fun begin(memberId: MemberId, key: String, requestHash: String): IdempotencyOutcome
    /** В транзакции с созданием брони: либо бронь и ключ, либо ничего. */
    suspend fun complete(memberId: MemberId, key: String, bookingId: BookingId, status: Int)
}
