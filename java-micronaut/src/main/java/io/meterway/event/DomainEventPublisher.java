package io.meterway.event;

import io.micronaut.context.event.ApplicationEventPublisher;
import io.micronaut.transaction.TransactionOperations;
import io.micronaut.transaction.support.TransactionSynchronization;
import jakarta.inject.Singleton;

import java.sql.Connection;

/**
 * Публикация доменного события после коммита.
 * <p>
 * Событие, опубликованное внутри транзакции, доходит до слушателей раньше, чем данные
 * становятся видны, а при откате остаётся опубликованным: уведомление ушло, счёта нет.
 * Вне транзакции публикация выполняется сразу — метод обязан работать в обоих случаях.
 */
@Singleton
public class DomainEventPublisher {

    private final ApplicationEventPublisher<Object> events;
    private final TransactionOperations<Connection> transactions;

    public DomainEventPublisher(ApplicationEventPublisher<Object> events,
                                TransactionOperations<Connection> transactions) {
        this.events = events;
        this.transactions = transactions;
    }

    public void publishAfterCommit(Object event) {
        transactions.findTransactionStatus().ifPresentOrElse(
                status -> status.registerSynchronization(new TransactionSynchronization() {
                    @Override
                    public void afterCommit() {
                        events.publishEvent(event);
                    }
                }),
                () -> events.publishEvent(event));
    }
}
