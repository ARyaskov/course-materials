package dev.atrium.ktor.plugins

import java.util.concurrent.atomic.AtomicBoolean

/** readiness=false с ApplicationStopPreparing: балансировщик перестаёт слать трафик до закрытия listener-а (уроки 14.5, 15.2). */
class Readiness {
    private val state = AtomicBoolean(false)
    var ready: Boolean
        get() = state.get()
        set(value) = state.set(value)
}
