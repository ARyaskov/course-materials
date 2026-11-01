package dev.atrium.ktor.di

import dev.atrium.application.ApplicationScope
import dev.atrium.application.CancelBooking
import dev.atrium.application.ConfirmBooking
import dev.atrium.application.CreateBooking
import dev.atrium.application.ExpirePendingBookings
import dev.atrium.application.ListMemberBookings
import dev.atrium.application.OccupancyTracker
import dev.atrium.application.RoomAvailabilityQuery
import dev.atrium.application.ports.BookingPolicy
import dev.atrium.application.ports.BookingRepository
import dev.atrium.application.ports.Clock
import dev.atrium.application.ports.EventPublisher
import dev.atrium.application.ports.IdGenerator
import dev.atrium.application.ports.PaymentGateway
import dev.atrium.application.ports.RoomRepository
import dev.atrium.application.ports.TransactionRunner
import dev.atrium.infrastructure.cache.CachedRoomRepository
import dev.atrium.infrastructure.concurrency.databaseDispatcher
import dev.atrium.infrastructure.ids.UuidV7IdGenerator
import dev.atrium.infrastructure.outbox.OutboxEventPublisher
import dev.atrium.infrastructure.outbox.OutboxRelay
import dev.atrium.infrastructure.events.BookingEventHandler
import dev.atrium.infrastructure.events.BookingEventSender
import dev.atrium.infrastructure.events.KafkaConsumerLoop
import dev.atrium.infrastructure.events.KafkaProducerSender
import dev.atrium.infrastructure.events.NotificationOutboxRepository
import dev.atrium.infrastructure.events.ProcessedEventRepository
import dev.atrium.infrastructure.postgres.JobLease
import dev.atrium.infrastructure.postgres.JdbcBackfillCheckpointRepository
import dev.atrium.infrastructure.postgres.JdbcUtilizationRepository
import dev.atrium.application.RoomUtilizationBackfill
import dev.atrium.application.ports.BackfillCheckpointRepository
import dev.atrium.application.ports.UtilizationRepository
import dev.atrium.ktor.plugins.prometheusRegistry
import org.apache.kafka.clients.consumer.ConsumerConfig
import org.apache.kafka.clients.consumer.KafkaConsumer
import org.apache.kafka.clients.producer.KafkaProducer
import org.apache.kafka.clients.producer.ProducerConfig
import org.apache.kafka.common.serialization.ByteArrayDeserializer
import org.apache.kafka.common.serialization.ByteArraySerializer
import org.apache.kafka.common.serialization.StringDeserializer
import org.apache.kafka.common.serialization.StringSerializer
import dev.atrium.infrastructure.paygate.PayGateClient
import dev.atrium.infrastructure.resilience.ResilientPaymentGateway
import dev.atrium.infrastructure.idempotency.JdbcIdempotencyStore
import dev.atrium.application.ports.IdempotencyStore
import dev.atrium.infrastructure.redis.AtriumRedis
import dev.atrium.infrastructure.redis.RedisLock
import dev.atrium.infrastructure.redis.RedisRateLimiter
import dev.atrium.infrastructure.postgres.JdbcBookingRepository
import dev.atrium.infrastructure.postgres.JdbcRoomRepository
import dev.atrium.infrastructure.postgres.JdbcTransactionRunner
import dev.atrium.ktor.config.AtriumConfig
import dev.atrium.ktor.config.loadConfig
import dev.atrium.ktor.di.buildOpenTelemetry
import dev.atrium.ktor.plugins.Readiness
import dev.atrium.application.ports.Metrics
import dev.atrium.application.ports.Tracing
import dev.atrium.infrastructure.metrics.MicrometerMetrics
import dev.atrium.infrastructure.tracing.OtelTracing
import io.micrometer.core.instrument.MeterRegistry
import io.opentelemetry.api.OpenTelemetry
import dev.atrium.ktor.config.atrium
import io.ktor.server.application.Application
import io.ktor.server.application.log
import io.ktor.server.plugins.di.dependencies
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import java.net.URI
import java.time.Duration
import java.time.Instant
import javax.sql.DataSource

/** Composition root app-ktor: единственный пакет, знающий реализации из infrastructure. */
fun Application.configureDependencies() {
    val config = loadConfig() // падает на старте с полным списком ошибок конфигурации (урок 14.4)

    dependencies {
        provide<AtriumConfig> { config }
        provide<Clock> { Clock { Instant.now() } }
        provide<IdGenerator> { UuidV7IdGenerator }
        provide<ApplicationScope> { ApplicationScope(onError = { this@configureDependencies.log.error("background task failed", it) }) }
        provide { Readiness() }
        provide<MeterRegistry> { prometheusRegistry }
        provide<Metrics> { MicrometerMetrics(resolve()) }
        provide<OpenTelemetry> { buildOpenTelemetry(config.telemetry.otlpEndpoint, config.telemetry.traceSampling, System.getenv("ATRIUM_ENV") ?: "dev") }
        provide<Tracing> { OtelTracing(resolve<OpenTelemetry>().getTracer("atrium")) }

        provide<DataSource> { hikariDataSource(config.database) }
        provide<CoroutineDispatcher>("db") { databaseDispatcher(config.database.poolSize) }
        provide<CoroutineDispatcher>("reports") { Dispatchers.IO.limitedParallelism(2) }
        provide<TransactionRunner> { JdbcTransactionRunner(resolve(), resolve("db")) }
        provide<BookingRepository> { JdbcBookingRepository(resolve(), resolve("db")) }
        provide<RoomRepository> { CachedRoomRepository(JdbcRoomRepository(resolve(), resolve("db")), resolve()) }
        provide<EventPublisher> { OutboxEventPublisher(resolve(), resolve("db")) }
        provide<PaymentGateway> {
            ResilientPaymentGateway(
                PayGateClient(URI.create(config.paygate.baseUrl), config.paygate.apiKey, requestTimeout = Duration.ofSeconds(config.paygate.timeoutSeconds)),
                prometheusRegistry,
                timeout = Duration.ofSeconds(config.paygate.timeoutSeconds),
            )
        }
        provide<IdempotencyStore> { JdbcIdempotencyStore(resolve(), resolve("db")) }
        provide { AtriumRedis(config.redis.url) }
        provide { RedisLock(resolve()) }
        provide { RedisRateLimiter(resolve()) }
        provide<BookingPolicy> {
            object : BookingPolicy {
                override val holdTtl = Duration.ofMinutes(config.booking.holdTtlMinutes)
                override val noShowGrace = Duration.ofMinutes(config.booking.noShowGraceMinutes)
            }
        }

        provide { CreateBooking(resolve(), resolve(), resolve(), resolve(), resolve(), resolve(), resolve()) }
        provide { ConfirmBooking(resolve(), resolve(), resolve(), resolve(), resolve(), resolve(), resolve()) }
        provide { CancelBooking(resolve(), resolve(), resolve(), resolve()) }
        provide { ListMemberBookings(resolve()) }
        provide { RoomAvailabilityQuery(resolve(), resolve()) }
        provide { ExpirePendingBookings(resolve(), resolve()) }
        provide { OccupancyTracker() }

        provide<KafkaProducer<String, ByteArray>> {
            KafkaProducer(
                mapOf(
                    ProducerConfig.BOOTSTRAP_SERVERS_CONFIG to config.kafka.bootstrap,
                    ProducerConfig.ACKS_CONFIG to "all",
                    ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG to true,
                ),
                StringSerializer(), ByteArraySerializer(),
            )
        }
        provide<KafkaConsumer<String, ByteArray>> {
            KafkaConsumer(
                mapOf(
                    ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG to config.kafka.bootstrap,
                    ConsumerConfig.GROUP_ID_CONFIG to "atrium-notify",
                    ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG to false,
                    ConsumerConfig.AUTO_OFFSET_RESET_CONFIG to "earliest",
                ),
                StringDeserializer(), ByteArrayDeserializer(),
            )
        }
        provide<BookingEventSender> { KafkaProducerSender(resolve()) }
        provide { JobLease(resolve(), resolve("db")) }
        provide { OutboxRelay(resolve(), resolve("db"), resolve(), resolve(), registry = prometheusRegistry) }
        provide { ProcessedEventRepository(resolve(), resolve("db")) }
        provide { NotificationOutboxRepository(resolve(), resolve("db")) }
        provide { BookingEventHandler(resolve(), resolve(), resolve(), resolve(), prometheusRegistry) }
        provide { KafkaConsumerLoop(resolve(), resolve(), resolve()) }
        provide<UtilizationRepository> { JdbcUtilizationRepository(resolve(), resolve("db")) }
        provide<BackfillCheckpointRepository> { JdbcBackfillCheckpointRepository(resolve(), resolve("db")) }
        provide { RoomUtilizationBackfill(resolve(), resolve(), resolve(), resolve(), resolve()) }

        cleanup<DataSource> { (it as? AutoCloseable)?.close() }
        cleanup<KafkaProducer<String, ByteArray>> { it.close() }
        cleanup<AtriumRedis> { it.close() }
    }
}
