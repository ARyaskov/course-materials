package dev.atrium.ktor.jobs

import dev.atrium.application.ApplicationScope
import dev.atrium.application.ExpirePendingBookings
import dev.atrium.application.ports.Clock
import dev.atrium.application.runCatchingCancellable
import dev.atrium.infrastructure.outbox.OutboxRelay
import dev.atrium.ktor.config.AtriumConfig
import io.ktor.server.application.Application
import io.ktor.server.application.log
import io.ktor.server.plugins.di.dependencies
import kotlinx.coroutines.CoroutineName
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

/** Циклы на корутинах: fixedDelay по построению, отмена через isActive/delay при остановке scope. */
fun Application.configureJobs() {
    val scope: ApplicationScope by dependencies
    val expire: ExpirePendingBookings by dependencies
    val relay: OutboxRelay by dependencies
    val clock: Clock by dependencies
    val config: AtriumConfig by dependencies

    scope.scope.launch(CoroutineName("expire-bookings")) {
        while (isActive) {
            runCatchingCancellable { expire.expireBatch(clock.now(), config.jobs.expireBatchSize) }
                .onFailure { log.error("job=expire-bookings failed", it) }
            delay(config.jobs.expireIntervalSeconds.seconds)
        }
    }

    scope.scope.launch(CoroutineName("outbox-relay")) {
        while (isActive) {
            runCatchingCancellable {
                while (relay.relayOnce() > 0) {
                }
            }
                .onFailure { log.error("job=outbox-relay failed", it) }
            delay(config.jobs.outboxIntervalMillis.milliseconds)
        }
    }
}
