package dev.atrium.infrastructure.metrics

import dev.atrium.application.ports.Metrics
import io.micrometer.core.instrument.Gauge
import io.micrometer.core.instrument.MeterRegistry
import io.micrometer.core.instrument.Tags
import io.micrometer.core.instrument.Timer
import io.micrometer.core.instrument.config.MeterFilter
import kotlinx.coroutines.CancellationException

class MicrometerMetrics(private val registry: MeterRegistry) : Metrics {
    init {
        // Страховка от кардинальности: больше 20 значений одного тега на метрику — остальные отбрасываются
        registry.config().meterFilter(MeterFilter.maximumAllowableTags("atrium", "reason", 20, MeterFilter.deny()))
        registry.config().meterFilter(MeterFilter.deny { id -> id.name.startsWith("atrium") && id.tags.any { it.key in FORBIDDEN_TAGS } })
    }

    override fun count(name: String, vararg tags: Pair<String, String>) =
        registry.counter(name, tags.toTags()).increment()

    override fun gauge(name: String, vararg tags: Pair<String, String>, supplier: () -> Number) {
        Gauge.builder(name) { supplier().toDouble() }.tags(tags.toTags()).register(registry)
    }

    /** Timer.start/stop вместо timer.record { }: block — suspend, корутина может сменить поток. */
    override suspend fun <T> timed(name: String, vararg tags: Pair<String, String>, block: suspend () -> T): T {
        val sample = Timer.start(registry)
        var outcome = "ok"
        try {
            return block()
        } catch (e: CancellationException) {
            outcome = "cancelled"
            throw e
        } catch (e: Exception) {
            outcome = "error"
            throw e
        } finally {
            sample.stop(registry.timer(name, tags.toTags().and("outcome", outcome)))
        }
    }

    private fun Array<out Pair<String, String>>.toTags(): Tags = Tags.of(map { (k, v) -> io.micrometer.core.instrument.Tag.of(k, v) })

    companion object {
        val FORBIDDEN_TAGS = setOf("bookingId", "memberId", "requestId", "booking.id", "member.id")
    }
}
