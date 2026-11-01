package dev.atrium.application.ports

/** Маркер открытой транзакции. Реализация в infrastructure держит JDBC Connection. */
interface Transaction

interface TransactionRunner {
    suspend fun <T> inTransaction(block: suspend context(Transaction) () -> T): T

    companion object {
        /** Без транзакций — для unit-тестов с in-memory портами. */
        val NONE: TransactionRunner = object : TransactionRunner {
            private val marker = object : Transaction {}
            override suspend fun <T> inTransaction(block: suspend context(Transaction) () -> T): T = context(marker) { block() }
        }
    }
}
