@file:JvmName("AtriumClients")

package dev.atrium.client

import kotlinx.coroutines.CoroutineName
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.future.future
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration
import java.util.concurrent.CompletableFuture
import java.util.function.Consumer
import kotlin.uuid.Uuid

/**
 * Клиент Atrium для Kotlin- и Java-потребителей (уроки 16.1, 16.5).
 * Одна реализация — suspend; Async (CompletableFuture) и Blocking — трёхстрочные адаптеры.
 */
@JvmSuppressWildcards
public class AtriumClient @JvmOverloads constructor(
    private val baseUrl: String,
    private val apiKey: String,
    private val timeout: Duration = Duration.ofSeconds(5),
    private val httpClient: HttpClient = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(3)).build(),
) : AutoCloseable {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO + CoroutineName("atrium-client"))
    private val transport = Transport(baseUrl, apiKey, timeout, httpClient)

    public suspend fun createBooking(request: CreateBookingRequest, idempotencyKey: String? = null): BookingResult =
        transport.post("/api/v1/bookings", request.toJson(), idempotencyKey).toBookingResult()

    public fun createBookingAsync(request: CreateBookingRequest, idempotencyKey: String? = null): CompletableFuture<BookingResult> =
        scope.future { createBooking(request, idempotencyKey) }

    /** Для virtual threads и CLI; не вызывать из реактивных event-loop-ов. */
    public fun createBookingBlocking(request: CreateBookingRequest, idempotencyKey: String? = null): BookingResult =
        runBlocking(Dispatchers.IO) { createBooking(request, idempotencyKey) }

    public suspend fun confirmBooking(id: Uuid): BookingResult = transport.post("/api/v1/bookings/$id/confirm", "", null).toBookingResult()
    public fun confirmBookingAsync(id: Uuid): CompletableFuture<BookingResult> = scope.future { confirmBooking(id) }
    public fun confirmBookingBlocking(id: Uuid): BookingResult = runBlocking(Dispatchers.IO) { confirmBooking(id) }

    /** List<Uuid> без wildcard-ов для Java — @JvmSuppressWildcards на классе. */
    public suspend fun listBookings(roomIds: List<Uuid>): List<BookingRef> =
        transport.get("/api/v1/bookings?roomId=${roomIds.joinToString(",")}").toBookingRefs()
    public fun listBookingsBlocking(roomIds: List<Uuid>): List<BookingRef> = runBlocking(Dispatchers.IO) { listBookings(roomIds) }

    /** Kotlin — Flow; Java — callback-адаптер, Flow без корутин бесполезен. */
    public fun occupancy(roomId: Uuid): Flow<OccupancyEvent> = transport.sse("/api/v1/rooms/$roomId/occupancy")

    public fun subscribeOccupancy(roomId: Uuid, consumer: Consumer<OccupancyEvent>): AutoCloseable {
        val job = scope.launch { occupancy(roomId).collect { consumer.accept(it) } }
        return AutoCloseable { job.cancel() }
    }

    override fun close() {
        scope.cancel("client closed")
    }

    public companion object {
        @JvmField public val DEFAULT_TIMEOUT: Duration = Duration.ofSeconds(5)

        @JvmStatic
        public fun fromEnvironment(): AtriumClient = AtriumClient(env("ATRIUM_BASE_URL"), env("ATRIUM_API_KEY"))

        private fun env(name: String): String = System.getenv(name) ?: throw IllegalStateException("$name is not set")
    }
}

/** Транспорт над JDK HttpClient: блокирующий send — под Dispatchers.IO внутри адаптера, не у вызывающего. */
internal class Transport(private val baseUrl: String, private val apiKey: String, private val timeout: Duration, private val http: HttpClient) {
    suspend fun post(path: String, body: String, idempotencyKey: String?): HttpResponse<String> = send(
        HttpRequest.newBuilder(URI.create(baseUrl + path)).timeout(timeout)
            .header("Authorization", "Bearer $apiKey").header("Content-Type", "application/json")
            .apply { if (idempotencyKey != null) header("Idempotency-Key", idempotencyKey) }
            .POST(HttpRequest.BodyPublishers.ofString(body)).build(),
    )

    suspend fun get(path: String): HttpResponse<String> =
        send(HttpRequest.newBuilder(URI.create(baseUrl + path)).timeout(timeout).header("Authorization", "Bearer $apiKey").GET().build())

    private suspend fun send(request: HttpRequest): HttpResponse<String> =
        withContext(Dispatchers.IO) { http.send(request, HttpResponse.BodyHandlers.ofString()) }

    fun sse(path: String): Flow<OccupancyEvent> = kotlinx.coroutines.flow.flow {
        val response = withContext(Dispatchers.IO) { http.send(HttpRequest.newBuilder(URI.create(baseUrl + path)).header("Authorization", "Bearer $apiKey").GET().build(), HttpResponse.BodyHandlers.ofLines()) }
        response.body().use { lines -> for (line in lines) if (line.startsWith("data:")) emit(Json.occupancyEvent(line.removePrefix("data:").trim())) }
    }
}
