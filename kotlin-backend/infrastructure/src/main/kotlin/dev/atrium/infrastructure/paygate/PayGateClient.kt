package dev.atrium.infrastructure.paygate

import dev.atrium.application.ports.PaymentGateway
import dev.atrium.application.ports.PaymentResult
import dev.atrium.domain.BookingId
import dev.atrium.domain.Money
import dev.atrium.domain.PaymentId
import dev.atrium.infrastructure.json.atriumJsonMapper
import dev.atrium.infrastructure.json.read
import java.io.IOException
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.future.await

/**
 * Клиент внешнего платёжного провайдера на JDK HttpClient (общий для Spring и Ktor).
 * Сетевые сбои ловятся здесь и превращаются в PaymentResult.Unavailable; CancellationException проходит наверх.
 * Retry, timeout и circuit breaker добавляются декоратором в главе 12.
 */
class PayGateClient(
    private val baseUrl: URI,
    private val apiKey: String,
    private val http: HttpClient = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build(),
    private val requestTimeout: Duration = Duration.ofSeconds(5),
) : PaymentGateway {

    private data class ChargeRequest(val bookingId: String, val amount: String, val currency: String)
    private data class ChargeResponse(val id: String)
    private data class RefundResponse(val id: String)
    private data class ErrorResponse(val reason: String)

    override suspend fun charge(bookingId: BookingId, amount: Money, idempotencyKey: String): PaymentResult = try {
        val body = atriumJsonMapper.writeValueAsString(ChargeRequest(bookingId.value.toString(), amount.amount.toPlainString(), amount.currency.currencyCode))
        val request = HttpRequest.newBuilder(baseUrl.resolve("/v1/charges"))
            .timeout(requestTimeout)
            .header("Authorization", "Bearer $apiKey")
            .header("Idempotency-Key", idempotencyKey)
            .header("Content-Type", "application/json")
            .POST(HttpRequest.BodyPublishers.ofString(body))
            .build()
        val response = http.sendAsync(request, HttpResponse.BodyHandlers.ofString()).await()
        when (response.statusCode()) {
            200, 201 -> PaymentResult.Charged(PaymentId(atriumJsonMapper.read<ChargeResponse>(response.body()).id))
            402 -> PaymentResult.Declined(atriumJsonMapper.read<ErrorResponse>(response.body()).reason)
            else -> PaymentResult.Unavailable("PayGate responded ${response.statusCode()}")
        }
    } catch (e: IOException) {
        PaymentResult.Unavailable(e.message ?: e.javaClass.simpleName)
    }

    override suspend fun refund(paymentId: PaymentId): PaymentResult = try {
        val request = HttpRequest.newBuilder(baseUrl.resolve("/v1/charges/${paymentId.value}/refund"))
            .timeout(requestTimeout)
            .header("Authorization", "Bearer $apiKey")
            .POST(HttpRequest.BodyPublishers.noBody())
            .build()
        val response = http.sendAsync(request, HttpResponse.BodyHandlers.ofString()).await()
        when (response.statusCode()) {
            200 -> PaymentResult.Refunded(PaymentId(atriumJsonMapper.read<RefundResponse>(response.body()).id))
            409 -> PaymentResult.Declined(atriumJsonMapper.read<ErrorResponse>(response.body()).reason)
            else -> PaymentResult.Unavailable("PayGate responded ${response.statusCode()}")
        }
    } catch (e: IOException) {
        PaymentResult.Unavailable(e.message ?: e.javaClass.simpleName)
    }
}
