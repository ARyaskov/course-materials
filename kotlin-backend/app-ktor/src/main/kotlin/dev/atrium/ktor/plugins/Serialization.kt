package dev.atrium.ktor.plugins

import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import kotlinx.serialization.json.Json

/** Один экземпляр Json на приложение: ContentNegotiation, тесты, Kafka — одно поведение. */
val atriumJson = Json {
    ignoreUnknownKeys = true // tolerant reader
    explicitNulls = false // null-поля не пишутся и трактуются как отсутствующие
    encodeDefaults = true // default-значения попадают в ответ
    isLenient = false
    coerceInputValues = false // "60" в Int — ошибка, а не приведение
}

fun Application.configureSerialization() {
    install(ContentNegotiation) {
        json(atriumJson)
    }
}
