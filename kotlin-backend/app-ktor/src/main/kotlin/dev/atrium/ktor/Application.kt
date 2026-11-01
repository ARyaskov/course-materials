package dev.atrium.ktor

import dev.atrium.ktor.di.configureDependencies
import dev.atrium.ktor.di.migrate
import dev.atrium.ktor.plugins.configureErrorPages
import dev.atrium.ktor.plugins.configureLifecycle
import dev.atrium.ktor.plugins.configureObservability
import dev.atrium.ktor.plugins.configureRouting
import dev.atrium.ktor.plugins.configureSerialization
import dev.atrium.ktor.plugins.configureTracing
import dev.atrium.ktor.jobs.configureJobs
import dev.atrium.infrastructure.events.KafkaConsumerLoop
import dev.atrium.application.ApplicationScope
import io.ktor.server.application.Application
import io.ktor.server.application.log
import io.ktor.server.plugins.di.dependencies

/**
 * --dry-run: собрать DI и завершиться — training run для CDS-архива в Dockerfile без БД и Kafka (урок 15.5).
 * Иначе — обычный EngineMain с application.yaml.
 */
fun main(args: Array<String>) {
    if ("--dry-run" in args) {
        System.setProperty("atrium.dryRun", "true")
        io.ktor.server.engine.embeddedServer(io.ktor.server.netty.Netty, port = 0) { configureSerialization(); configureErrorPages(); configureObservability(); configureDependencies() }
            .also { it.start(wait = false) }.stop(0, 0)
        return
    }
    io.ktor.server.netty.EngineMain.main(args)
}

/** Модуль — явная последовательность: сериализация и ошибки → зависимости → миграции → маршруты. */
fun Application.module() {
    configureSerialization()
    configureErrorPages()
    configureObservability()
    configureDependencies()
    val openTelemetry: io.opentelemetry.api.OpenTelemetry by dependencies
    val dataSource: javax.sql.DataSource by dependencies
    configureTracing(openTelemetry)
    migrate(dataSource)
    configureLifecycle()
    configureRouting()
    configureJobs()
    val scope: ApplicationScope by dependencies
    val consumerLoop: KafkaConsumerLoop by dependencies
    consumerLoop.start(scope.scope)
    val startedAt = System.currentTimeMillis()
    monitor.subscribe(io.ktor.server.application.ApplicationStarted) {
        log.info("app.startup.phase module={}ms jvm={}ms", System.currentTimeMillis() - startedAt, java.lang.management.ManagementFactory.getRuntimeMXBean().uptime)
    }
}
