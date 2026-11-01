package dev.atrium.spring.config

import dev.atrium.application.CancelBooking
import dev.atrium.application.ConfirmBooking
import dev.atrium.application.CreateBooking
import dev.atrium.application.ports.BookingRepository
import dev.atrium.application.ports.Clock
import dev.atrium.application.ports.PaymentGateway
import dev.atrium.application.ports.RoomRepository
import dev.atrium.infrastructure.cache.CachedRoomRepository
import dev.atrium.infrastructure.concurrency.databaseDispatcher
import dev.atrium.infrastructure.ids.UuidV7IdGenerator
import dev.atrium.infrastructure.postgres.JdbcBookingRepository
import dev.atrium.infrastructure.postgres.JdbcRoomRepository
import dev.atrium.infrastructure.paygate.LocalPaymentGateway
import org.springframework.context.support.beans
import java.time.Instant

/**
 * Bean definition DSL — альтернатива @Configuration для урока 7.5. К приложению не подключён:
 * основной composition root — PersistenceConfig/UseCaseConfig, где работают @Conditional* и автоконфигурации.
 */
@Suppress("DEPRECATION")
val atriumBeans = beans {
    bean<UuidV7IdGenerator>()
    bean<Clock> { Clock { Instant.now() } }
    bean { databaseDispatcher(ref<AtriumProperties>().database.poolSize) }
    bean<BookingRepository> { JdbcBookingRepository(ref(), ref()) }
    bean<RoomRepository> { CachedRoomRepository(JdbcRoomRepository(ref(), ref()), ref()) }
    bean { CreateBooking(ref(), ref(), ref(), ref(), ref()) }
    bean { ConfirmBooking(ref(), ref(), ref(), ref(), ref()) }
    bean { CancelBooking(ref(), ref(), ref(), ref()) }
    profile("local") {
        bean<PaymentGateway> { LocalPaymentGateway() }
    }
}
