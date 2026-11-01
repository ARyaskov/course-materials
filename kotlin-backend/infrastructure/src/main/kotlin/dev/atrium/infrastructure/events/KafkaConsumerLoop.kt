package dev.atrium.infrastructure.events

import dev.atrium.application.ports.TransactionRunner
import dev.atrium.application.runCatchingCancellable
import dev.atrium.application.transactional
import dev.atrium.infrastructure.json.atriumJsonMapper
import dev.atrium.infrastructure.json.read
import io.github.oshai.kotlinlogging.KotlinLogging
import kotlinx.coroutines.CoroutineName
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.slf4j.MDCContext
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.apache.kafka.common.errors.WakeupException
import org.apache.kafka.clients.consumer.KafkaConsumer
import java.time.Duration

private val log = KotlinLogging.logger {}

/** Consumer на kafka-clients для app-ktor: poll на IO, обработка в транзакции, commitSync после батча — at-least-once. */
class KafkaConsumerLoop(
    private val consumer: KafkaConsumer<String, ByteArray>,
    private val handler: BookingEventHandler,
    private val transactions: TransactionRunner,
    private val topic: String = "atrium.bookings",
) {
    private var loop: Job? = null

    /** Для readiness (урок 15.2): цикл запущен и не завершён. */
    val isRunning: Boolean get() = loop?.isActive == true

    fun start(scope: CoroutineScope): Job = scope.launch(CoroutineName("kafka-consumer")) {
        consumer.subscribe(listOf(topic))
        try {
            while (isActive) {
                val records = withContext(Dispatchers.IO) { consumer.poll(Duration.ofMillis(500)) }
                for (record in records) {
                    val event = atriumJsonMapper.read<BookingEventDto>(String(record.value()))
                    val requestId = record.headers().lastHeader("requestId")?.value()?.decodeToString() ?: event.eventId
                    // NonCancellable: остановка не должна оборвать запись между handle и commit; MDCContext — requestId инициатора в логах (урок 14.1)
                    withContext(NonCancellable + MDCContext(mapOf("requestId" to requestId, "eventId" to event.eventId))) {
                        runCatchingCancellable { transactions.transactional { handler.handle(event) } }
                            .onFailure { log.error(it) { "event ${event.eventId} failed at ${record.partition()}:${record.offset()}" }; throw it }
                    }
                }
                if (!records.isEmpty) withContext(Dispatchers.IO) { consumer.commitSync() }
            }
        } catch (_: WakeupException) {
            // stop(): прерван блокирующий poll
        } finally {
            withContext(NonCancellable + Dispatchers.IO) { consumer.close() } // close() коммитит и покидает группу сразу, без ожидания session.timeout
        }
    }.also { loop = it }

    /** Graceful (урок 14.5): wakeup() прерывает poll, текущая запись дорабатывается под NonCancellable, close() коммитит. */
    suspend fun stop(timeout: kotlin.time.Duration) {
        val job = loop ?: return
        job.cancel()
        consumer.wakeup()
        withTimeoutOrNull(timeout) { job.join() } ?: log.warn { "kafka consumer did not stop in $timeout" }
    }
}
