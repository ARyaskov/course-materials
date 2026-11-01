package dev.atrium.spring.config

import dev.atrium.application.ApplicationScope
import io.github.oshai.kotlinlogging.KotlinLogging
import kotlinx.coroutines.runBlocking
import org.springframework.context.SmartLifecycle
import org.springframework.stereotype.Component
import kotlin.time.Duration.Companion.seconds

private val log = KotlinLogging.logger {}

/** Останавливается после веб-сервера и Kafka-контейнеров, до DataSource (урок 14.5). */
@Component
class ApplicationScopeLifecycle(private val scope: ApplicationScope) : SmartLifecycle {
    @Volatile private var running = false

    @Volatile final var finished: Boolean? = null
        private set

    override fun start() {
        running = true
    }

    override fun isRunning() = running

    override fun getPhase() = SmartLifecycle.DEFAULT_PHASE - 100

    override fun stop(callback: Runnable) {
        running = false
        Thread.ofVirtual().start {
            finished = runBlocking { scope.shutdown(grace = 15.seconds) }
            log.atInfo {
                message = "app.scope.stopped"
                payload = mapOf("finished" to finished)
            }
            callback.run()
        }
    }

    override fun stop() = stop {}
}
