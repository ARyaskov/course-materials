package dev.atrium.application

import kotlin.time.Duration
import kotlin.time.TimeSource

inline fun <T> measure(onDone: (Duration) -> Unit, block: () -> T): T {
    val mark = TimeSource.Monotonic.markNow()
    try {
        return block()
    } finally {
        onDone(mark.elapsedNow())
    }
}
