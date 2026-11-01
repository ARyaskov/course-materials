package dev.atrium.ktor

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import dev.atrium.ktor.plugins.Readiness
import dev.atrium.ktor.routes.healthRoutes
import io.kotest.matchers.shouldBe
import io.ktor.client.request.get
import io.ktor.http.HttpStatusCode
import io.ktor.server.routing.routing
import io.ktor.server.testing.testApplication
import kotlinx.coroutines.Dispatchers
import org.junit.jupiter.api.Test

/** 503 до готовности, 200 после, 503 с закрытым пулом (урок 15.2). */
class HealthRoutesTest {
    private val dataSource = HikariDataSource(
        HikariConfig().apply {
            jdbcUrl = Postgres.container.jdbcUrl
            username = Postgres.container.username
            password = Postgres.container.password
            maximumPoolSize = 2
        },
    )

    @Test
    fun `readiness follows flag and database`() = testApplication {
        val readiness = Readiness()
        application { routing { healthRoutes(readiness, dataSource, consumer = null, dbDispatcher = Dispatchers.IO) } }

        client.get("/readyz").status shouldBe HttpStatusCode.ServiceUnavailable
        readiness.ready = true
        client.get("/readyz").status shouldBe HttpStatusCode.OK
        client.get("/healthz").status shouldBe HttpStatusCode.OK

        dataSource.close()
        client.get("/readyz").status shouldBe HttpStatusCode.ServiceUnavailable
        client.get("/healthz").status shouldBe HttpStatusCode.OK // liveness от БД не зависит
    }
}
