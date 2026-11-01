package dev.atrium.infrastructure.notify

import dev.atrium.application.ports.Notification
import dev.atrium.application.ports.NotificationSender
import dev.atrium.application.runCatchingCancellable
import io.github.oshai.kotlinlogging.KotlinLogging
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ClosedSendChannelException
import kotlinx.coroutines.launch

private val log = KotlinLogging.logger {}

/**
 * Очередь уведомлений внутри процесса: обработчик кладёт и отвечает клиенту,
 * `workers` корутин отправляют с ограниченной параллельностью. Буфер ограничен —
 * при переполнении enqueue возвращает false, а не растит память.
 */
class NotificationDispatcher(
    scope: CoroutineScope,
    private val sender: NotificationSender,
    workers: Int = 5,
    capacity: Int = 1_000,
) {
    private val queue = Channel<Notification>(capacity)

    init {
        repeat(workers) { index ->
            scope.launch {
                for (notification in queue) {
                    runCatchingCancellable { sender.send(notification) }
                        .onFailure { log.warn(it) { "worker-$index: notification ${notification.id} failed" } }
                }
            }
        }
    }

    fun enqueue(notification: Notification): Boolean =
        try {
            queue.trySend(notification).isSuccess
        } catch (_: ClosedSendChannelException) {
            false
        }

    fun close() = queue.close()
}
