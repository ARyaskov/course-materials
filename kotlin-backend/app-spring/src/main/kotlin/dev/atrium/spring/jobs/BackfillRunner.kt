package dev.atrium.spring.jobs

import dev.atrium.application.RoomUtilizationBackfill
import kotlinx.coroutines.runBlocking
import org.slf4j.LoggerFactory
import org.springframework.boot.ApplicationArguments
import org.springframework.boot.ApplicationRunner
import org.springframework.boot.SpringApplication
import org.springframework.context.ConfigurableApplicationContext
import org.springframework.context.annotation.Profile
import org.springframework.stereotype.Component
import java.time.Instant

/** Профиль backfill: тот же образ, другой entrypoint — веб-сервер, планировщик и consumer отключены. */
@Component
@Profile("backfill")
class BackfillRunner(private val backfill: RoomUtilizationBackfill, private val context: ConfigurableApplicationContext) : ApplicationRunner {
    private val log = LoggerFactory.getLogger(javaClass)

    override fun run(args: ApplicationArguments) {
        val runId = args.getOptionValues("run-id")?.single() ?: error("--run-id is required")
        val from = Instant.parse(args.getOptionValues("from")?.single() ?: error("--from is required"))
        val to = Instant.parse(args.getOptionValues("to")?.single() ?: Instant.now().toString())
        val summary = runBlocking { backfill.run(runId, from, to) }
        log.info("backfill {} done: processed={}", runId, summary.processed)
        SpringApplication.exit(context, { 0 })
    }
}
