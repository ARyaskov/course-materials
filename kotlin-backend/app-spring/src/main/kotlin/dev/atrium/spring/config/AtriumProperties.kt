package dev.atrium.spring.config

import jakarta.validation.Valid
import jakarta.validation.constraints.AssertTrue
import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import jakarta.validation.constraints.NotBlank
import org.springframework.boot.context.properties.ConfigurationProperties
import org.springframework.boot.context.properties.bind.DefaultValue
import org.springframework.validation.annotation.Validated
import java.net.URI
import java.time.Duration

@ConfigurationProperties("atrium")
@Validated
data class AtriumProperties(
    @field:Valid val booking: Booking = Booking(),
    @field:Valid val paygate: PayGate,
    @field:Valid val notify: Notify,
    @field:Valid val database: Database = Database(),
    @field:Valid val features: Features = Features(),
    @field:Valid val redis: Redis = Redis(),
) {
    data class Booking(
        @DefaultValue("15m") val holdTtl: Duration = Duration.ofMinutes(15),
        @DefaultValue("15m") val noShowGrace: Duration = Duration.ofMinutes(15),
        @field:Min(1) val expireBatchSize: Int = 100,
    ) {
        init {
            require(holdTtl in Duration.ofMinutes(1)..Duration.ofHours(2)) { "atrium.booking.hold-ttl must be 1m..2h, was $holdTtl" }
        }
    }

    data class PayGate(
        val baseUrl: URI,
        @field:NotBlank val apiKey: String,
        @DefaultValue("5s") val timeout: Duration = Duration.ofSeconds(5),
    ) {
        override fun toString() = "PayGate(baseUrl=$baseUrl, apiKey=***, timeout=$timeout)" // секрет не попадает в логи (урок 14.4)
    }

    data class Notify(
        val baseUrl: URI,
        @field:NotBlank val apiKey: String,
        val batchSize: Int = 20,
        @field:Min(1) @field:Max(20) val workers: Int = 5,
    ) {
        init {
            require(batchSize in 1..100) { "atrium.notify.batch-size must be 1..100, was $batchSize" }
        }
    }

    data class Database(
        @field:Min(2) @field:Max(100) val poolSize: Int = 15,
    )

    data class Redis(val url: String = "redis://localhost:6379")

    /** Флаги: default — выключено; читаются в конфигурации бинов, не в use case-ах; список с датами — docs/features.md. */
    data class Features(
        val corporateDepositWaiver: Boolean = false,
        val sseOccupancy: Boolean = true,
        val redisRateLimit: Boolean = false,
        val jooqReads: Boolean = false,
        val noShowDetection: Boolean = false,
    )

    @AssertTrue(message = "atrium.redis.url is required when features.redis-rate-limit is on")
    fun isRedisConfiguredWhenNeeded(): Boolean = !features.redisRateLimit || redis.url.isNotBlank()
}
