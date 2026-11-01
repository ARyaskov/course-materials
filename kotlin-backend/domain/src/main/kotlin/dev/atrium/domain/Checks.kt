package dev.atrium.domain

import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.contract

fun requireActive(booking: Booking): Booking {
    require(booking.isActive) { "Booking ${booking.id} is not active: ${booking.status}" }
    return booking
}

@OptIn(ExperimentalContracts::class)
fun BookingStatus.isPending(): Boolean {
    contract { returns(true) implies (this@isPending is BookingStatus.Pending) }
    return this is BookingStatus.Pending
}

fun unreachable(reason: String): Nothing = error("Unreachable: $reason")
