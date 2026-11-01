package dev.atrium.spring

import dev.atrium.application.ports.PaymentGateway
import dev.atrium.application.testing.FakePaymentGateway
import dev.atrium.spring.api.BookingResponse
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.resttestclient.autoconfigure.AutoConfigureRestTestClient
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.context.SpringBootTest.WebEnvironment.RANDOM_PORT
import org.springframework.boot.test.context.TestConfiguration
import org.springframework.boot.testcontainers.service.connection.ServiceConnection
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Primary
import org.springframework.http.MediaType
import org.springframework.test.web.servlet.client.RestTestClient
import org.springframework.test.web.servlet.client.expectBody
import org.testcontainers.junit.jupiter.Container
import org.testcontainers.junit.jupiter.Testcontainers
import org.testcontainers.postgresql.PostgreSQLContainer

@SpringBootTest(webEnvironment = RANDOM_PORT)
@AutoConfigureRestTestClient
@Testcontainers
class BookingFlowIntegrationTest(@Autowired private val client: RestTestClient) {

    companion object {
        @Container
        @ServiceConnection
        @JvmStatic
        val postgres = PostgreSQLContainer("postgres:18")

        // Комната из миграции V900__seed_dev.sql (применяется только с профилем test)
        const val SEEDED_ROOM = "00000000-0000-0000-0000-000000000101"
    }

    @TestConfiguration
    class Fakes {
        @Bean @Primary fun paymentGateway(): PaymentGateway = FakePaymentGateway()
    }

    @Test
    fun `create then confirm booking`() {
        val created = client.post().uri("/api/v1/bookings")
            .contentType(MediaType.APPLICATION_JSON)
            .body("""{"roomId": "$SEEDED_ROOM", "startsAt": "2027-01-10T10:00:00Z"}""")
            .exchange()
            .expectStatus().isCreated
            .expectBody<BookingResponse>().returnResult().responseBody!!

        client.post().uri("/api/v1/bookings/${created.id}/confirm")
            .exchange()
            .expectStatus().isOk
            .expectBody().jsonPath("$.status").isEqualTo("CONFIRMED")
    }
}
