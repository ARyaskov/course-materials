package dev.atrium.client

import kotlinx.serialization.json.Json as KotlinxJson
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.net.http.HttpResponse
import java.time.Instant
import kotlin.uuid.Uuid

/** Ручной маппинг JSON: модель клиента — обычные классы без @Serializable, чтобы форма API не диктовала форму классов. */
internal object Json {
    private val json = KotlinxJson { ignoreUnknownKeys = true }

    fun parse(text: String): JsonObject = json.parseToJsonElement(text).jsonObject

    fun bookingRef(o: JsonObject): BookingRef = BookingRef(
        id = Uuid.parse(o["id"]!!.jsonPrimitive.content),
        roomId = Uuid.parse(o["roomId"]!!.jsonPrimitive.content),
        startsAt = Instant.parse(o["startsAt"]!!.jsonPrimitive.content),
        endsAt = Instant.parse(o["endsAt"]!!.jsonPrimitive.content),
        status = o["status"]!!.jsonPrimitive.content,
    )

    fun problem(o: JsonObject): Problem = Problem(
        type = o["type"]?.jsonPrimitive?.content ?: "about:blank",
        title = o["title"]?.jsonPrimitive?.content ?: "",
        status = o["status"]?.jsonPrimitive?.content?.toIntOrNull() ?: 0,
        detail = o["detail"]?.jsonPrimitive?.content,
    )

    fun occupancyEvent(text: String): OccupancyEvent = parse(text).let {
        OccupancyEvent(Uuid.parse(it["roomId"]!!.jsonPrimitive.content), it["occupied"]!!.jsonPrimitive.content.toBoolean(), Instant.parse(it["at"]!!.jsonPrimitive.content))
    }
}

internal fun CreateBookingRequest.toJson(): String = buildJsonObject {
    put("roomId", roomId.toString())
    put("startsAt", startsAt.toString())
    put("durationMinutes", durationMinutes)
}.toString()

internal fun HttpResponse<String>.toBookingResult(): BookingResult = when (statusCode()) {
    in 200..299 -> BookingResult.Created(Json.bookingRef(Json.parse(body())))
    in 400..499 -> BookingResult.Rejected(Json.problem(Json.parse(body())))
    else -> throw AtriumClientException("Atrium responded ${statusCode()}", statusCode())
}

internal fun HttpResponse<String>.toBookingRefs(): List<BookingRef> {
    if (statusCode() !in 200..299) throw AtriumClientException("Atrium responded ${statusCode()}", statusCode())
    return kotlinx.serialization.json.Json.parseToJsonElement(body()).jsonObject["items"]!!.let { items ->
        (items as kotlinx.serialization.json.JsonArray).map { Json.bookingRef(it.jsonObject) }
    }
}

/** Инфраструктурная ошибка (5xx, сеть) — исключение; ожидаемый отказ (4xx) — BookingResult.Rejected. */
public class AtriumClientException(message: String, public val status: Int) : RuntimeException(message)
