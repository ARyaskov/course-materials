package dev.atrium.application.ports

/** Порт трассировки: span на use case и на внешний вызов; идентификаторы допустимы в атрибутах (урок 14.3). */
interface Tracing {
    suspend fun <T> span(name: String, attributes: Map<String, Any> = emptyMap(), block: suspend SpanScope.() -> T): T

    object None : Tracing {
        override suspend fun <T> span(name: String, attributes: Map<String, Any>, block: suspend SpanScope.() -> T): T = NoSpan.block()
        private object NoSpan : SpanScope {
            override fun event(name: String, attributes: Map<String, Any>) = Unit
            override fun attribute(key: String, value: Any) = Unit
        }
    }
}

interface SpanScope {
    fun event(name: String, attributes: Map<String, Any> = emptyMap())
    fun attribute(key: String, value: Any)
}
