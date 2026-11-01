package dev.atrium.ktor.plugins

import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.createApplicationPlugin
import io.ktor.server.plugins.callid.callId
import io.ktor.server.request.header
import io.ktor.util.AttributeKey
import kotlinx.coroutines.slf4j.MDCContext
import kotlinx.coroutines.withContext
import org.slf4j.MDC
import kotlin.uuid.Uuid

val RequestIdKey = AttributeKey<String>("RequestId")

class RequestIdConfig {
    var header: String = "X-Request-Id"
}

/**
 * Учебный плагин (урок 8.5): один requestId на запрос — в атрибутах, в ответе и в MDC.
 * В module() используется встроенный CallId + CallLogging; этот плагин показывает механизм.
 */
val RequestId = createApplicationPlugin("RequestId", ::RequestIdConfig) {
    val headerName = pluginConfig.header
    onCall { call ->
        val id = call.request.header(headerName)?.takeIf { it.length in 8..128 } ?: Uuid.random().toString()
        call.attributes.put(RequestIdKey, id)
        call.response.headers.append(headerName, id)
        MDC.put("requestId", id)
    }
    onCallRespond { _, _ -> MDC.remove("requestId") }
}

val ApplicationCall.requestId: String get() = attributes.getOrNull(RequestIdKey) ?: callId ?: "-"

/** Обработчики, переключающие dispatcher, теряют MDC — оборачивать корутину явно. */
suspend fun <T> ApplicationCall.withRequestMdc(block: suspend () -> T): T =
    withContext(MDCContext(mapOf("requestId" to requestId))) { block() }
