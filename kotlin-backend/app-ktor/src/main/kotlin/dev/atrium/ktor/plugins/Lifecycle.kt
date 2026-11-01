package dev.atrium.ktor.plugins

import com.zaxxer.hikari.HikariDataSource
import dev.atrium.application.ApplicationScope
import dev.atrium.infrastructure.events.KafkaConsumerLoop
import io.ktor.server.application.Application
import io.ktor.server.application.ApplicationStarted
import io.ktor.server.application.ApplicationStopPreparing
import io.ktor.server.application.ApplicationStopped
import io.ktor.server.application.ApplicationStopping
import io.ktor.server.application.log
import io.ktor.server.plugins.di.dependencies
import kotlinx.coroutines.runBlocking
import javax.sql.DataSource
import kotlin.time.Duration.Companion.seconds

/**
 * Порядок остановки (урок 14.5): readiness=false → Netty перестаёт принимать (grace из yaml) →
 * consumer коммитит и выходит из группы → фон с таймаутом → пул соединений последним.
 */
fun Application.configureLifecycle() {
    val scope: ApplicationScope by dependencies
    val dataSource: DataSource by dependencies
    val readiness: Readiness by dependencies
    val consumer: KafkaConsumerLoop? = runCatching { val c: KafkaConsumerLoop by dependencies; c }.getOrNull()

    monitor.subscribe(ApplicationStarted) {
        readiness.ready = true
        log.info("app.started pool={}", (dataSource as? HikariDataSource)?.poolName)
    }
    monitor.subscribe(ApplicationStopPreparing) {
        readiness.ready = false
        log.info("app.stopping")
    }
    monitor.subscribe(ApplicationStopping) {
        runBlocking { // поток остановки, вне event-loop Netty
            consumer?.stop(timeout = 10.seconds)
            val finished = scope.shutdown(grace = 15.seconds)
            if (!finished) log.warn("app.scope.timeout")
            log.info("app.scope.stopped finished={}", finished)
        }
    }
    monitor.subscribe(ApplicationStopped) {
        (dataSource as? AutoCloseable)?.close()
        log.info("app.stopped")
    }
}
