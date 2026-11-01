package dev.atrium.ktor.config

import io.ktor.server.application.Application
import io.ktor.server.config.ApplicationConfig
import io.ktor.server.config.getAs
import kotlinx.serialization.Serializable

@Serializable
data class AtriumConfig(
    val database: Database,
    val booking: Booking = Booking(),
    val paygate: PayGate,
    val notify: Notify,
    val jobs: Jobs = Jobs(),
    val kafka: Kafka = Kafka(),
    val redis: Redis = Redis(),
    val telemetry: Telemetry = Telemetry(),
    val features: Features = Features(),
) {
    @Serializable data class Database(val url: String, val user: String, val password: String, val poolSize: Int = 15)
    @Serializable data class Booking(val holdTtlMinutes: Long = 15, val noShowGraceMinutes: Long = 15)
    @Serializable data class PayGate(val baseUrl: String, val apiKey: String, val timeoutSeconds: Long = 5) {
        override fun toString() = "PayGate(baseUrl=$baseUrl, apiKey=***, timeoutSeconds=$timeoutSeconds)"
    }
    @Serializable data class Redis(val url: String = "redis://localhost:6379")
    @Serializable data class Kafka(val bootstrap: String = "localhost:9092")
    @Serializable data class Jobs(val expireIntervalSeconds: Long = 30, val outboxIntervalMillis: Long = 500, val expireBatchSize: Int = 100)
    @Serializable data class Notify(val baseUrl: String, val apiKey: String, val workers: Int = 5) {
        init {
            require(workers in 1..20) { "atrium.notify.workers must be 1..20, was $workers" }
        }
        override fun toString() = "Notify(baseUrl=$baseUrl, apiKey=***, workers=$workers)"
    }
    @Serializable data class Telemetry(val otlpEndpoint: String = "http://localhost:4318", val traceSampling: Double = 0.1, val excludedPaths: String = "/healthz,/metrics")
    /** Флаги — типизированная конфигурация с безопасным default=false; читаются только при сборке зависимостей (урок 14.4). */
    @Serializable data class Features(val redisRateLimit: Boolean = false, val jooqReads: Boolean = false, val noShowDetection: Boolean = false)

    init {
        require(booking.holdTtlMinutes in 1..120) { "atrium.booking.holdTtlMinutes must be 1..120, was ${booking.holdTtlMinutes}" }
    }

    /** Все ошибки разом — приложение падает на старте с полным списком, а не с первой (урок 14.4). */
    fun validate(env: String = System.getenv("ATRIUM_ENV") ?: "dev"): List<String> = buildList {
        if (database.poolSize !in 2..100) add("atrium.database.poolSize must be in 2..100, got ${database.poolSize}")
        if (paygate.apiKey.isBlank()) add("atrium.paygate.apiKey is blank")
        if (paygate.baseUrl.contains("paygate.example.com") && env != "prod") add("atrium.paygate.baseUrl points to production outside prod")
        if (env == "prod" && paygate.apiKey == "dev-key") add("atrium.paygate.apiKey is the dev placeholder in prod")
        if (telemetry.traceSampling !in 0.0..1.0) add("atrium.telemetry.traceSampling must be in 0..1")
        if (features.redisRateLimit && redis.url.isBlank()) add("atrium.redis.url is required when features.redisRateLimit is on")
    }
}

fun ApplicationConfig.atrium(): AtriumConfig = config("atrium").getAs<AtriumConfig>()

fun Application.loadConfig(): AtriumConfig {
    val config = environment.config.atrium()
    val errors = config.validate()
    check(errors.isEmpty()) { "invalid configuration:\n" + errors.joinToString("\n") }
    return config
}
