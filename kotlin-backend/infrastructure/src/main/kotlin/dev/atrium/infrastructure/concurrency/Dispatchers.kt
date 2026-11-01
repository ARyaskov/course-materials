package dev.atrium.infrastructure.concurrency

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.asCoroutineDispatcher
import java.util.concurrent.Executors

/**
 * Dispatcher для блокирующего JDBC на virtual threads: поток на задачу, дешёвая блокировка.
 * Параллелизм ограничен размером пула соединений — очередь ждёт в корутинах, а не в getConnection.
 */
fun databaseDispatcher(poolSize: Int): CoroutineDispatcher =
    Executors.newVirtualThreadPerTaskExecutor().asCoroutineDispatcher().limitedParallelism(poolSize)
