package dev.atrium.ktor.di

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import dev.atrium.ktor.config.AtriumConfig
import org.flywaydb.core.Flyway
import javax.sql.DataSource

fun hikariDataSource(config: AtriumConfig.Database): DataSource = HikariDataSource(
    HikariConfig().apply {
        jdbcUrl = config.url
        username = config.user
        password = config.password
        maximumPoolSize = config.poolSize
        connectionInitSql = "SET statement_timeout = '5s'; SET idle_in_transaction_session_timeout = '30s'" // урок 17.4
        connectionTimeout = 3_000
        poolName = "atrium"
        leakDetectionThreshold = 30_000
    },
)

/** Миграции при старте — как spring.flyway в app-spring; вызывается из module() до маршрутов. */
fun migrate(dataSource: DataSource) {
    Flyway.configure().dataSource(dataSource).locations("classpath:db/migration").load().migrate()
}
