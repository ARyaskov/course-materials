package dev.atrium.spring.jobs

import dev.atrium.application.ApplicationScope
import dev.atrium.infrastructure.outbox.OutboxRelay
import kotlinx.coroutines.CoroutineName
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Component

@Component
class OutboxRelayJob(private val relay: OutboxRelay, private val scope: ApplicationScope) {
    private val running = Mutex()

    @Scheduled(fixedDelayString = "\${atrium.jobs.outbox-interval:500ms}")
    fun run() {
        if (!running.tryLock()) return
        scope.scope.launch(CoroutineName("outbox-relay")) {
            try {
                // Добираем, пока есть что публиковать.
                while (relay.relayOnce() > 0) {
                }
            } finally {
                running.unlock()
            }
        }
    }
}
