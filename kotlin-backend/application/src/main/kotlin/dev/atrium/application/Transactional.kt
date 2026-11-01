package dev.atrium.application

import dev.atrium.application.ports.Transaction
import dev.atrium.application.ports.TransactionRunner

/** Граница транзакции use case. crossinline: блок вызывается внутри лямбды, уходящей объектом в runner. */
suspend inline fun <T> TransactionRunner.transactional(crossinline block: suspend context(Transaction) () -> T): T =
    inTransaction { block() }
