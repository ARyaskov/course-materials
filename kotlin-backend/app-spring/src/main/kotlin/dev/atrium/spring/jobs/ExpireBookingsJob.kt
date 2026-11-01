package dev.atrium.spring.jobs

import dev.atrium.application.ApplicationScope
import dev.atrium.application.ExpirePendingBookings
import dev.atrium.application.ports.Clock
import dev.atrium.spring.config.AtriumProperties
import io.micrometer.core.instrument.Counter
import io.micrometer.core.instrument.MeterRegistry
import io.micrometer.core.instrument.Timer
import kotlinx.coroutines.CoroutineName
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import org.slf4j.LoggerFactory
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Component
import kotlin.uuid.Uuid

/** @Scheduled запускает suspend-задачу в ApplicationScope: отмена при shutdown, ошибки в handler scope. */
@Component
class ExpireBookingsJob(
    private val expire: ExpirePendingBookings,
    private val clock: Clock,
    private val properties: AtriumProperties,
    private val scope: ApplicationScope,
    registry: MeterRegistry,
) {
    private val log = LoggerFactory.getLogger(javaClass)
    private val timer = Timer.builder("atrium.jobs.duration").tag("job", "expire-bookings").register(registry)
    private val expired = Counter.builder("atrium.jobs.expired").register(registry)
    private val skipped = Counter.builder("atrium.jobs.skipped").tag("job", "expire-bookings").tag("reason", "overlap").register(registry)
    private val running = Mutex()

    @Scheduled(fixedDelayString = "\${atrium.jobs.expire-interval:30s}")
    fun run() {
        if (!running.tryLock()) { skipped.increment(); return } // предыдущий запуск ещё идёт
        val runId = Uuid.random().toString().take(8)
        scope.scope.launch(CoroutineName("expire-bookings-$runId")) {
            try {
                val sample = Timer.start()
                val count = expire.expireBatch(clock.now(), properties.booking.expireBatchSize)
                sample.stop(timer)
                expired.increment(count.toDouble())
                if (count > 0) log.info("job=expire-bookings runId={} expired={}", runId, count)
            } finally {
                running.unlock()
            }
        }
    }
}
