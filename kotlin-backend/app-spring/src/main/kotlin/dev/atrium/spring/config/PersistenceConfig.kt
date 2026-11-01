package dev.atrium.spring.config

import dev.atrium.application.ports.BookingRepository
import dev.atrium.application.ports.Clock
import dev.atrium.application.ports.RoomRepository
import dev.atrium.application.ports.TransactionRunner
import dev.atrium.infrastructure.cache.CachedRoomRepository
import dev.atrium.infrastructure.concurrency.databaseDispatcher
import dev.atrium.infrastructure.postgres.JdbcBookingRepository
import dev.atrium.infrastructure.postgres.JdbcRoomRepository
import dev.atrium.infrastructure.postgres.JdbcTransactionRunner
import dev.atrium.application.OccupancyTracker
import dev.atrium.application.ports.EventPublisher
import dev.atrium.application.ports.BackfillCheckpointRepository
import dev.atrium.application.ports.UtilizationRepository
import dev.atrium.infrastructure.events.BookingEventHandler
import dev.atrium.infrastructure.events.BookingEventSender
import dev.atrium.infrastructure.events.NotificationOutboxRepository
import dev.atrium.infrastructure.events.ProcessedEventRepository
import dev.atrium.infrastructure.outbox.OutboxEventPublisher
import dev.atrium.infrastructure.outbox.OutboxRelay
import dev.atrium.infrastructure.postgres.JdbcBackfillCheckpointRepository
import dev.atrium.infrastructure.postgres.JdbcUtilizationRepository
import dev.atrium.infrastructure.postgres.JobLease
import io.micrometer.core.instrument.MeterRegistry
import dev.atrium.application.ports.IdempotencyStore
import dev.atrium.infrastructure.idempotency.JdbcIdempotencyStore
import dev.atrium.infrastructure.redis.AtriumRedis
import dev.atrium.infrastructure.redis.RedisLock
import dev.atrium.infrastructure.redis.RedisRateLimiter
import kotlinx.coroutines.CoroutineDispatcher
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import javax.sql.DataSource

/** Composition root persistence-слоя: реализации из infrastructure без Spring-аннотаций. */
@Configuration(proxyBeanMethods = false)
class PersistenceConfig {
    @Bean
    fun dbDispatcher(properties: AtriumProperties): CoroutineDispatcher = databaseDispatcher(properties.database.poolSize)

    @Bean
    fun transactionRunner(dataSource: DataSource, dbDispatcher: CoroutineDispatcher): TransactionRunner =
        JdbcTransactionRunner(dataSource, dbDispatcher)

    @Bean
    fun bookingRepository(dataSource: DataSource, dbDispatcher: CoroutineDispatcher): BookingRepository =
        JdbcBookingRepository(dataSource, dbDispatcher)

    @Bean
    fun roomRepository(dataSource: DataSource, dbDispatcher: CoroutineDispatcher, clock: Clock): RoomRepository =
        CachedRoomRepository(JdbcRoomRepository(dataSource, dbDispatcher), clock)

    @Bean
    fun eventPublisher(dataSource: DataSource, dbDispatcher: CoroutineDispatcher): EventPublisher = OutboxEventPublisher(dataSource, dbDispatcher)

    @Bean
    fun jobLease(dataSource: DataSource, dbDispatcher: CoroutineDispatcher): JobLease = JobLease(dataSource, dbDispatcher)

    @Bean
    fun outboxRelay(dataSource: DataSource, dbDispatcher: CoroutineDispatcher, sender: BookingEventSender, lease: JobLease, registry: MeterRegistry): OutboxRelay =
        OutboxRelay(dataSource, dbDispatcher, sender, lease, registry = registry)

    @Bean
    fun processedEvents(dataSource: DataSource, dbDispatcher: CoroutineDispatcher) = ProcessedEventRepository(dataSource, dbDispatcher)

    @Bean
    fun notificationOutbox(dataSource: DataSource, dbDispatcher: CoroutineDispatcher) = NotificationOutboxRepository(dataSource, dbDispatcher)

    @Bean
    fun bookingEventHandler(p: ProcessedEventRepository, n: NotificationOutboxRepository, b: BookingRepository, t: OccupancyTracker, r: MeterRegistry) =
        BookingEventHandler(p, n, b, t, r)

    @Bean
    fun utilizationRepository(dataSource: DataSource, dbDispatcher: CoroutineDispatcher): UtilizationRepository = JdbcUtilizationRepository(dataSource, dbDispatcher)

    @Bean
    fun backfillCheckpoints(dataSource: DataSource, dbDispatcher: CoroutineDispatcher): BackfillCheckpointRepository = JdbcBackfillCheckpointRepository(dataSource, dbDispatcher)

    @Bean
    fun idempotencyStore(dataSource: DataSource, dbDispatcher: CoroutineDispatcher): IdempotencyStore = JdbcIdempotencyStore(dataSource, dbDispatcher)

    @Bean(destroyMethod = "close")
    fun atriumRedis(properties: AtriumProperties): AtriumRedis = AtriumRedis(properties.redis.url)

    @Bean fun redisLock(redis: AtriumRedis) = RedisLock(redis)
    @Bean fun redisRateLimiter(redis: AtriumRedis) = RedisRateLimiter(redis)
}
