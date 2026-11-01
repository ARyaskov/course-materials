package dev.atrium.infrastructure.json

import tools.jackson.databind.json.JsonMapper
import tools.jackson.module.kotlin.KotlinModule

/** Общий JsonMapper (Jackson 3) для outbox, Kafka и HTTP-клиентов вне Spring-контекста. */
val atriumJsonMapper: JsonMapper = JsonMapper.builder()
    .addModule(KotlinModule.Builder().build())
    .findAndAddModules()
    .build()

inline fun <reified T : Any> JsonMapper.read(json: String): T = readValue(json, T::class.java)
