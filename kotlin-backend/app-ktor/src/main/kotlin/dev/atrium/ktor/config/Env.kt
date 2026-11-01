package dev.atrium.ktor.config

import kotlin.properties.ReadOnlyProperty
import kotlin.reflect.KProperty

/** Делегат чтения переменной окружения: имя свойства попадает в сообщение об ошибке. */
class EnvVar<T>(
    private val name: String,
    private val default: T? = null,
    private val parse: (String) -> T,
) : ReadOnlyProperty<Any?, T> {
    override fun getValue(thisRef: Any?, property: KProperty<*>): T {
        val raw = System.getenv(name)
        return when {
            raw != null -> parse(raw)
            default != null -> default
            else -> error("Environment variable $name is required for ${property.name}")
        }
    }
}

fun env(name: String, default: String? = null): EnvVar<String> = EnvVar(name, default) { it }
fun envInt(name: String, default: Int? = null): EnvVar<Int> = EnvVar(name, default) { it.toInt() }

object AtriumEnv {
    val databaseUrl: String by env("ATRIUM_DATABASE_URL", "jdbc:postgresql://localhost:5432/atrium")
    val holdTtlMinutes: Int by envInt("ATRIUM_BOOKING_HOLD_TTL_MINUTES", 15)
}

/** Секрет: переменная окружения, иначе файл /run/secrets/<lowercase name> (Docker/Kubernetes secrets); урок 14.4. */
fun secret(name: String, secretsDir: java.nio.file.Path = java.nio.file.Path.of("/run/secrets")): ReadOnlyProperty<Any?, String> =
    EnvVar(name, null) { it }.let { envVar ->
        object : ReadOnlyProperty<Any?, String> {
            override fun getValue(thisRef: Any?, property: KProperty<*>): String {
                System.getenv(name)?.let { return it }
                val file = secretsDir.resolve(name.lowercase())
                if (java.nio.file.Files.isReadable(file)) return java.nio.file.Files.readString(file).trim()
                return envVar.getValue(thisRef, property)
            }
        }
    }
