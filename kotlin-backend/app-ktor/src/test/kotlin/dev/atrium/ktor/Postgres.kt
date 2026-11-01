package dev.atrium.ktor

import org.testcontainers.postgresql.PostgreSQLContainer

/** Один контейнер на JVM тестов: стартует при первом обращении, Testcontainers остановит его через Ryuk. */
object Postgres {
    val container: PostgreSQLContainer by lazy {
        PostgreSQLContainer("postgres:18").withReuse(true).also { it.start() }
    }
}
