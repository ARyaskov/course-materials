package dev.atrium.application.ports

/** Порт метрик: use case-ы считают бизнес-события, не зная о Micrometer (урок 14.2). Теги — только конечные множества значений. */
interface Metrics {
    fun count(name: String, vararg tags: Pair<String, String>)
    fun gauge(name: String, vararg tags: Pair<String, String>, supplier: () -> Number)
    suspend fun <T> timed(name: String, vararg tags: Pair<String, String>, block: suspend () -> T): T

    object None : Metrics {
        override fun count(name: String, vararg tags: Pair<String, String>) = Unit
        override fun gauge(name: String, vararg tags: Pair<String, String>, supplier: () -> Number) = Unit
        override suspend fun <T> timed(name: String, vararg tags: Pair<String, String>, block: suspend () -> T): T = block()
    }
}
