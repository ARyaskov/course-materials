package dev.atrium.spring.config

import dev.atrium.application.ApplicationScope
import dev.atrium.application.CancelBooking
import dev.atrium.application.ConfirmBooking
import dev.atrium.application.CreateBooking
import dev.atrium.application.ExpirePendingBookings
import dev.atrium.application.ListMemberBookings
import dev.atrium.application.OccupancyTracker
import dev.atrium.application.RoomAvailabilityQuery
import dev.atrium.application.RoomUtilizationBackfill
import dev.atrium.application.ports.BackfillCheckpointRepository
import dev.atrium.application.ports.UtilizationRepository
import dev.atrium.application.ports.BookingPolicy
import dev.atrium.application.ports.BookingRepository
import dev.atrium.application.ports.Clock
import dev.atrium.application.ports.EventPublisher
import dev.atrium.application.ports.Metrics
import dev.atrium.application.ports.Tracing
import dev.atrium.infrastructure.metrics.MicrometerMetrics
import dev.atrium.infrastructure.tracing.OtelTracing
import io.micrometer.core.instrument.MeterRegistry
import io.opentelemetry.api.OpenTelemetry
import dev.atrium.application.ports.IdGenerator
import dev.atrium.application.ports.PaymentGateway
import dev.atrium.application.ports.RoomRepository
import dev.atrium.application.ports.TransactionRunner
import dev.atrium.application.ports.IdempotencyStore
import dev.atrium.infrastructure.resilience.ResilientPaymentGateway
import dev.atrium.infrastructure.paygate.PayGateClient
import dev.atrium.infrastructure.ids.UuidV7IdGenerator
import org.slf4j.LoggerFactory
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import java.time.Instant

@Configuration(proxyBeanMethods = false)
class UseCaseConfig {
    private val log = LoggerFactory.getLogger(javaClass)

    @Bean fun clock(): Clock = Clock { Instant.now() }
    @Bean fun idGenerator(): IdGenerator = UuidV7IdGenerator
    @Bean fun applicationScope(): ApplicationScope = ApplicationScope(onError = { log.error("background task failed", it) })
    @Bean fun occupancyTracker(): OccupancyTracker = OccupancyTracker()

    @Bean
    fun bookingPolicy(properties: AtriumProperties): BookingPolicy = object : BookingPolicy {
        override val holdTtl = properties.booking.holdTtl
        override val noShowGrace = properties.booking.noShowGrace
    }

    @Bean
    fun createBooking(b: BookingRepository, r: RoomRepository, e: EventPublisher, i: IdGenerator, c: Clock, t: TransactionRunner, s: IdempotencyStore) = CreateBooking(b, r, e, i, c, t, s)

    @Bean
    fun confirmBooking(b: BookingRepository, r: RoomRepository, p: PaymentGateway, e: EventPublisher, c: Clock, m: Metrics, t: Tracing) = ConfirmBooking(b, r, p, e, c, m, t)

    @Bean
    fun metrics(registry: MeterRegistry): Metrics = MicrometerMetrics(registry)

    @Bean
    fun tracing(openTelemetry: OpenTelemetry): Tracing = OtelTracing(openTelemetry.getTracer("atrium"))

    @Bean
    fun cancelBooking(b: BookingRepository, p: PaymentGateway, e: EventPublisher, c: Clock) = CancelBooking(b, p, e, c)

    @Bean fun listMemberBookings(b: BookingRepository) = ListMemberBookings(b)

    @Bean
    fun paymentGateway(properties: AtriumProperties, registry: MeterRegistry): PaymentGateway =
        ResilientPaymentGateway(PayGateClient(properties.paygate.baseUrl, properties.paygate.apiKey, requestTimeout = properties.paygate.timeout), registry, timeout = properties.paygate.timeout)
    @Bean fun roomAvailabilityQuery(r: RoomRepository, b: BookingRepository) = RoomAvailabilityQuery(r, b)
    @Bean fun expirePendingBookings(b: BookingRepository, e: EventPublisher) = ExpirePendingBookings(b, e)
    @Bean fun utilizationBackfill(b: BookingRepository, u: UtilizationRepository, c: BackfillCheckpointRepository, t: TransactionRunner, clock: Clock) = RoomUtilizationBackfill(b, u, c, t, clock)
}
