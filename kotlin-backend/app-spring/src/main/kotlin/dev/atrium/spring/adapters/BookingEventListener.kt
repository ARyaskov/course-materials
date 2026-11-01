package dev.atrium.spring.adapters

import dev.atrium.application.ports.TransactionRunner
import dev.atrium.application.transactional
import dev.atrium.infrastructure.events.BookingEventDto
import dev.atrium.infrastructure.events.BookingEventHandler
import kotlinx.coroutines.runBlocking
import org.apache.kafka.clients.consumer.ConsumerRecord
import org.springframework.kafka.annotation.KafkaListener
import org.springframework.kafka.support.Acknowledgment
import org.springframework.stereotype.Component

/**
 * Listener работает на потоке контейнера (виртуальном с Boot 4.1). runBlocking здесь оправдан:
 * корутинная транзакция JdbcTransactionRunner внутри, ack — только после коммита.
 */
@Component
class BookingEventListener(private val handler: BookingEventHandler, private val transactions: TransactionRunner) {

    @KafkaListener(topics = ["atrium.bookings"], groupId = "atrium-notify", concurrency = "3")
    fun on(record: ConsumerRecord<String, BookingEventDto>, ack: Acknowledgment) {
        runBlocking { transactions.transactional { handler.handle(record.value()) } }
        ack.acknowledge()
    }
}
