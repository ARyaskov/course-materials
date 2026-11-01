package dev.atrium.infrastructure.events

import dev.atrium.infrastructure.json.atriumJsonMapper
import kotlinx.coroutines.suspendCancellableCoroutine
import org.apache.kafka.clients.producer.KafkaProducer
import org.apache.kafka.clients.producer.ProducerRecord
import org.apache.kafka.clients.producer.RecordMetadata
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Продюсер на kafka-clients: один экземпляр на приложение, suspend-обёртка над callback с поддержкой отмены. */
class KafkaProducerSender(private val producer: KafkaProducer<String, ByteArray>, private val topic: String = "atrium.bookings") : BookingEventSender {
    override suspend fun send(event: BookingEventDto) {
        producer.sendSuspending(ProducerRecord(topic, event.bookingId, atriumJsonMapper.writeValueAsBytes(event)))
    }

    fun close() = producer.close()
}

suspend fun KafkaProducer<String, ByteArray>.sendSuspending(record: ProducerRecord<String, ByteArray>): RecordMetadata =
    suspendCancellableCoroutine { cont ->
        val future = send(record) { metadata, error ->
            if (error != null) cont.resumeWithException(error) else cont.resume(metadata)
        }
        cont.invokeOnCancellation { future.cancel(true) }
    }
